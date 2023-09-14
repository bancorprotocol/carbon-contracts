// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { MathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { MathEx } from "../utility/MathEx.sol";
import { InvalidIndices } from "../utility/Utils.sol";
import { Token } from "../token/Token.sol";
import { Pair } from "./Pairs.sol";
import { IVoucher } from "../voucher/interfaces/IVoucher.sol";
import { PPM_RESOLUTION } from "../utility/Constants.sol";
import { MAX_GAP } from "../utility/Constants.sol";

/**
 * @dev:
 *
 * a strategy consists of two orders:
 * - order 0 sells `y0` units of token 0 at a marginal rate `M0` ranging between `L0` and `H0`
 * - order 1 sells `y1` units of token 1 at a marginal rate `M1` ranging between `L1` and `H1`
 *
 * rate symbols:
 * - `L0` indicates the lowest value of one wei of token 0 in units of token 1
 * - `H0` indicates the highest value of one wei of token 0 in units of token 1
 * - `M0` indicates the marginal value of one wei of token 0 in units of token 1
 * - `L1` indicates the lowest value of one wei of token 1 in units of token 0
 * - `H1` indicates the highest value of one wei of token 1 in units of token 0
 * - `M1` indicates the marginal value of one wei of token 1 in units of token 0
 *
 * the term "one wei" serves here as a simplification of "an amount tending to zero",
 * hence the rate values above are all theoretical.
 * moreover, since trade calculation is based on the square roots of the rates,
 * an order doesn't actually hold the rate values, but a modified version of them.
 * for each rate `r`, the order maintains:
 * - mantissa: the value of the 48 most significant bits of `floor(sqrt(r) * 2 ^ 48)`
 * - exponent: the number of the remaining (least significant) bits, limited up to 48
 * this allows for rates between ~12.6e-28 and ~7.92e+28, at an average resolution of ~2.81e+14.
 * it also ensures that every rate value `r` is supported if and only if `1 / r` is supported.
 * however, it also yields a certain degree of accuracy loss as soon as the order is created.
 *
 * encoding / decoding scheme:
 * - `b(x) = bit-length of x`
 * - `c(x) = max(b(x) - 48, 0)`
 * - `f(x) = floor(sqrt(x) * (1 << 48))`
 * - `g(x) = f(x) >> c(f(x)) << c(f(x))`
 * - `e(x) = (x >> c(x)) | (c(x) << 48)`
 * - `d(x) = (x & ((1 << 48) - 1)) << (x >> 48)`
 *
 * let the following denote:
 * - `L = g(lowest rate)`
 * - `H = g(highest rate)`
 * - `M = g(marginal rate)`
 *
 * then the order maintains:
 * - `y = current liquidity`
 * - `z = current liquidity * (H - L) / (M - L)`
 * - `A = e(H - L)`
 * - `B = e(L)`
 *
 * and the order reflects:
 * - `L = d(B)`
 * - `H = d(B + A)`
 * - `M = d(B + A * y / z)`
 *
 * upon trading on a given order in a given strategy:
 * - the value of `y` in the given order decreases
 * - the value of `y` in the other order increases
 * - the value of `z` in the other order may increase
 * - the values of all other parameters remain unchanged
 *
 * given a source amount `x`, the expected target amount is:
 * - theoretical formula: `M ^ 2 * x * y / (M * (M - L) * x + y)`
 * - implemented formula: `x * (A * y + B * z) ^ 2 / (A * x * (A * y + B * z) + z ^ 2)`
 *
 * given a target amount `x`, the required source amount is:
 * - theoretical formula: `x * y / (M * (L - M) * x + M ^ 2 * y)`
 * - implemented formula: `x * z ^ 2 / ((A * y + B * z) * (A * y + B * z - A * x))`
 *
 * fee scheme:
 * +-------------------+---------------------------------+---------------------------------+
 * | trade function    | trader transfers to contract    | contract transfers to trader    |
 * +-------------------+---------------------------------+---------------------------------+
 * | bySourceAmount(x) | trader transfers to contract: x | p = expectedTargetAmount(x)     |
 * |                   |                                 | q = p * (100 - fee%) / 100      |
 * |                   |                                 | contract transfers to trader: q |
 * |                   |                                 | contract retains as fee: p - q  |
 * +-------------------+---------------------------------+---------------------------------+
 * | byTargetAmount(x) | p = requiredSourceAmount(x)     | contract transfers to trader: x |
 * |                   | q = p * 100 / (100 - fee%)      |                                 |
 * |                   | trader transfers to contract: q |                                 |
 * |                   | contract retains as fee: q - p  |                                 |
 * +-------------------+---------------------------------+---------------------------------+
 */

// solhint-disable var-name-mixedcase
struct Order {
    uint128 y;
    uint128 z;
    uint64 A;
    uint64 B;
}
// solhint-enable var-name-mixedcase

struct TradeTokens {
    Token source;
    Token target;
}

struct Strategy {
    uint256 id;
    address owner;
    Token[2] tokens;
    Order[2] orders;
}

struct TradeAction {
    uint256 strategyId;
    uint128 amount;
}

// strategy update reasons
uint8 constant STRATEGY_UPDATE_REASON_EDIT = 0;
uint8 constant STRATEGY_UPDATE_REASON_TRADE = 1;

abstract contract Strategies is Initializable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using Address for address payable;
    using MathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;

    error NativeAmountMismatch();
    error BalanceMismatch();
    error GreaterThanMaxInput();
    error LowerThanMinReturn();
    error InsufficientCapacity();
    error InsufficientLiquidity();
    error InvalidRate();
    error InvalidTradeActionStrategyId();
    error InvalidTradeActionAmount();
    error OrderDisabled();
    error OutDated();

    struct SourceAndTargetAmounts {
        uint128 sourceAmount;
        uint128 targetAmount;
    }

    struct TradeParams {
        address trader;
        TradeTokens tokens;
        bool byTargetAmount;
        uint128 constraint;
        uint256 txValue;
        Pair pair;
        uint128 sourceAmount;
        uint128 targetAmount;
    }

    uint256 private constant ONE = 1 << 48;

    uint256 private constant ORDERS_INVERTED_FLAG = 1 << 255;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 2000; // 0.2%

    // total number of strategies
    uint128 private _strategyCounter;

    // the global trading fee (in units of PPM)
    uint32 internal _tradingFeePPM;

    // mapping between a strategy to its packed orders
    mapping(uint256 => uint256[3]) private _packedOrdersByStrategyId;

    // mapping between a pair id to its strategies ids
    mapping(uint128 => EnumerableSetUpgradeable.UintSet) private _strategyIdsByPairIdStorage;

    // accumulated fees per token
    mapping(Token => uint256) internal _accumulatedFees;

    // mapping between a pair id to its custom trading fee (in units of PPM)
    mapping(uint128 pairId => uint32 fee) internal _customTradingFeePPM;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 5] private __gap;

    /**
     * @dev triggered when the network fee is updated
     */
    event TradingFeePPMUpdated(uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev triggered when the custom trading fee for a given pair is updated
     */
    event PairTradingFeePPMUpdated(Token indexed token0, Token indexed token1, uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev triggered when a strategy is created
     */
    event StrategyCreated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

    /**
     * @dev triggered when a strategy is deleted
     */
    event StrategyDeleted(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

    /**
     * @dev triggered when a strategy is updated
     */
    event StrategyUpdated(
        uint256 indexed id,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1,
        uint8 reason
    );

    /**
     * @dev triggered when tokens are traded
     */
    event TokensTraded(
        address indexed trader,
        Token indexed sourceToken,
        Token indexed targetToken,
        uint256 sourceAmount,
        uint256 targetAmount,
        uint128 tradingFeeAmount,
        bool byTargetAmount
    );

    /**
     * @dev triggered when fees are withdrawn
     */
    event FeesWithdrawn(Token indexed token, address indexed recipient, uint256 indexed amount, address sender);

    // solhint-disable func-name-mixedcase
    /**
     * @dev initializes the contract and its parents
     */
    function __Strategies_init() internal onlyInitializing {
        __Strategies_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __Strategies_init_unchained() internal onlyInitializing {
        _setTradingFeePPM(DEFAULT_TRADING_FEE_PPM);
    }

    // solhint-enable func-name-mixedcase

    /**
     * @dev creates a new strategy
     */
    function _createStrategy(
        IVoucher voucher,
        Token[2] memory tokens,
        Order[2] calldata orders,
        Pair memory pair,
        address owner,
        uint256 value
    ) internal returns (uint256) {
        // transfer funds
        _validateDepositAndRefundExcessNativeToken(tokens[0], owner, orders[0].y, value, true);
        _validateDepositAndRefundExcessNativeToken(tokens[1], owner, orders[1].y, value, true);

        // store id
        uint128 counter = _strategyCounter + 1;
        _strategyCounter = counter;
        uint256 id = _strategyId(pair.id, counter);
        _strategyIdsByPairIdStorage[pair.id].add(id);

        // store orders
        bool ordersInverted = tokens[0] == pair.tokens[1];
        _packedOrdersByStrategyId[id] = _packOrders(orders, ordersInverted);

        // mint voucher
        voucher.mint(owner, id);

        // emit event
        emit StrategyCreated({
            id: id,
            owner: owner,
            token0: tokens[0],
            token1: tokens[1],
            order0: orders[0],
            order1: orders[1]
        });

        return id;
    }

    /**
     * @dev updates an existing strategy
     */
    function _updateStrategy(
        uint256 strategyId,
        Order[2] calldata currentOrders,
        Order[2] calldata newOrders,
        Pair memory pair,
        address owner,
        uint256 value
    ) internal {
        // prepare storage variable
        uint256[3] storage packedOrders = _packedOrdersByStrategyId[strategyId];
        uint256[3] memory packedOrdersMemory = packedOrders;
        (Order[2] memory orders, bool ordersInverted) = _unpackOrders(packedOrdersMemory);

        // revert if the strategy mutated since this tx was sent
        if (!_equalStrategyOrders(currentOrders, orders)) {
            revert OutDated();
        }

        // store new values if necessary
        uint256[3] memory newPackedOrders = _packOrders(newOrders, ordersInverted);
        if (packedOrdersMemory[0] != newPackedOrders[0]) {
            packedOrders[0] = newPackedOrders[0];
        }
        if (packedOrdersMemory[1] != newPackedOrders[1]) {
            packedOrders[1] = newPackedOrders[1];
        }
        if (packedOrdersMemory[2] != newPackedOrders[2]) {
            packedOrders[2] = newPackedOrders[2];
        }

        // deposit and withdraw
        Token[2] memory sortedTokens = _sortStrategyTokens(pair, ordersInverted);
        for (uint256 i = 0; i < 2; i = uncheckedInc(i)) {
            Token token = sortedTokens[i];
            if (newOrders[i].y < orders[i].y) {
                // liquidity decreased - withdraw the difference
                uint128 delta = orders[i].y - newOrders[i].y;
                _withdrawFunds(token, payable(owner), delta);
            } else if (newOrders[i].y > orders[i].y) {
                // liquidity increased - deposit the difference
                uint128 delta = newOrders[i].y - orders[i].y;
                _validateDepositAndRefundExcessNativeToken(token, owner, delta, value, true);
            }

            // refund native token when there's no deposit in the order
            // note that deposit handles refunds internally
            if (value > 0 && token.isNative() && newOrders[i].y <= orders[i].y) {
                payable(address(owner)).sendValue(value);
            }
        }

        // emit event
        emit StrategyUpdated({
            id: strategyId,
            token0: sortedTokens[0],
            token1: sortedTokens[1],
            order0: newOrders[0],
            order1: newOrders[1],
            reason: STRATEGY_UPDATE_REASON_EDIT
        });
    }

    /**
     * @dev deletes a strategy
     */
    function _deleteStrategy(uint256 strategyId, IVoucher voucher, Pair memory pair) internal {
        Strategy memory strategy = _strategy(strategyId, voucher, pair);

        // burn the voucher nft token
        voucher.burn(strategy.id);

        // clear storage
        delete _packedOrdersByStrategyId[strategy.id];
        _strategyIdsByPairIdStorage[pair.id].remove(strategy.id);

        // withdraw funds
        _withdrawFunds(strategy.tokens[0], payable(strategy.owner), strategy.orders[0].y);
        _withdrawFunds(strategy.tokens[1], payable(strategy.owner), strategy.orders[1].y);

        // emit event
        emit StrategyDeleted({
            id: strategy.id,
            owner: strategy.owner,
            token0: strategy.tokens[0],
            token1: strategy.tokens[1],
            order0: strategy.orders[0],
            order1: strategy.orders[1]
        });
    }

    /**
     * @dev perform trade, update affected strategies
     *
     * requirements:
     *
     * - the caller must have approved the source token
     */
    function _trade(TradeAction[] calldata tradeActions, TradeParams memory params) internal {
        bool isTargetToken0 = params.tokens.target == params.pair.tokens[0];

        // process trade actions
        for (uint256 i = 0; i < tradeActions.length; i = uncheckedInc(i)) {
            // prepare variables
            uint128 amount = tradeActions[i].amount;
            uint256 strategyId = tradeActions[i].strategyId;
            uint256[3] storage packedOrders = _packedOrdersByStrategyId[strategyId];
            uint256[3] memory packedOrdersMemory = packedOrders;
            (Order[2] memory orders, bool ordersInverted) = _unpackOrders(packedOrdersMemory);

            _validateTradeParams(params.pair.id, strategyId, amount);

            (Order memory targetOrder, Order memory sourceOrder) = isTargetToken0 == ordersInverted
                ? (orders[1], orders[0])
                : (orders[0], orders[1]);

            // calculate the orders new values
            (uint128 sourceAmount, uint128 targetAmount) = _singleTradeActionSourceAndTargetAmounts(
                targetOrder,
                amount,
                params.byTargetAmount
            );

            // handled specifically for a custom error message
            if (targetOrder.y < targetAmount) {
                revert InsufficientLiquidity();
            }

            // update the orders with the new values
            // safe since it's checked above
            unchecked {
                targetOrder.y -= targetAmount;
            }

            sourceOrder.y += sourceAmount;
            if (sourceOrder.z < sourceOrder.y) {
                sourceOrder.z = sourceOrder.y;
            }

            // store new values if necessary
            uint256[3] memory newPackedOrders = _packOrders(orders, ordersInverted);

            // both y values are in slot 0, so it has definitely changed
            packedOrders[0] = newPackedOrders[0];

            // one of the z values is in slot 1, so it has possibly changed
            if (packedOrdersMemory[1] != newPackedOrders[1]) {
                packedOrders[1] = newPackedOrders[1];
            }

            // the other z value has possibly changed only if the first one hasn't
            if (packedOrdersMemory[2] != newPackedOrders[2]) {
                packedOrders[2] = newPackedOrders[2];
            }

            // emit update event
            emit StrategyUpdated({
                id: strategyId,
                token0: params.pair.tokens[ordersInverted ? 1 : 0],
                token1: params.pair.tokens[ordersInverted ? 0 : 1],
                order0: orders[0],
                order1: orders[1],
                reason: STRATEGY_UPDATE_REASON_TRADE
            });

            params.sourceAmount += sourceAmount;
            params.targetAmount += targetAmount;
        }

        // apply trading fee
        uint128 tradingFeeAmount;
        if (params.byTargetAmount) {
            uint128 amountIncludingFee = _addFee(params.sourceAmount, params.pair.id);
            tradingFeeAmount = amountIncludingFee - params.sourceAmount;
            params.sourceAmount = amountIncludingFee;
            if (params.sourceAmount > params.constraint) {
                revert GreaterThanMaxInput();
            }
            _accumulatedFees[params.tokens.source] += tradingFeeAmount;
        } else {
            uint128 amountExcludingFee = _subtractFee(params.targetAmount, params.pair.id);
            tradingFeeAmount = params.targetAmount - amountExcludingFee;
            params.targetAmount = amountExcludingFee;
            if (params.targetAmount < params.constraint) {
                revert LowerThanMinReturn();
            }
            _accumulatedFees[params.tokens.target] += tradingFeeAmount;
        }

        // transfer funds
        _validateDepositAndRefundExcessNativeToken(
            params.tokens.source,
            params.trader,
            params.sourceAmount,
            params.txValue,
            false
        );
        _withdrawFunds(params.tokens.target, payable(params.trader), params.targetAmount);

        // tokens traded successfully, emit event
        emit TokensTraded({
            trader: params.trader,
            sourceToken: params.tokens.source,
            targetToken: params.tokens.target,
            sourceAmount: params.sourceAmount,
            targetAmount: params.targetAmount,
            tradingFeeAmount: tradingFeeAmount,
            byTargetAmount: params.byTargetAmount
        });
    }

    /**
     * @dev calculates the required amount plus fee
     */
    function _addFee(uint128 amount, uint128 pairId) private view returns (uint128) {
        uint32 tradingFeePPM = _getPairTradingFeePPM(pairId);
        // divide the input amount by `1 - fee`
        return MathEx.mulDivC(amount, PPM_RESOLUTION, PPM_RESOLUTION - tradingFeePPM).toUint128();
    }

    /**
     * @dev calculates the expected amount minus fee
     */
    function _subtractFee(uint128 amount, uint128 pairId) private view returns (uint128) {
        uint32 tradingFeePPM = _getPairTradingFeePPM(pairId);
        // multiply the input amount by `1 - fee`
        return MathEx.mulDivF(amount, PPM_RESOLUTION - tradingFeePPM, PPM_RESOLUTION).toUint128();
    }

    /**
     * @dev get the custom trading fee ppm for a given pair (returns default trading fee if not set for pair)
     */
    function _getPairTradingFeePPM(uint128 pairId) internal view returns (uint32) {
        uint32 customTradingFeePPM = _customTradingFeePPM[pairId];
        return customTradingFeePPM == 0 ? _tradingFeePPM : customTradingFeePPM;
    }

    /**
     * @dev calculates and returns the total source and target amounts of a trade, including fees
     */
    function _tradeSourceAndTargetAmounts(
        TradeTokens memory tokens,
        TradeAction[] calldata tradeActions,
        Pair memory pair,
        bool byTargetAmount
    ) internal view returns (SourceAndTargetAmounts memory totals) {
        bool isTargetToken0 = tokens.target == pair.tokens[0];

        // process trade actions
        for (uint256 i = 0; i < tradeActions.length; i = uncheckedInc(i)) {
            // prepare variables
            uint128 amount = tradeActions[i].amount;
            uint256 strategyId = tradeActions[i].strategyId;
            uint256[3] memory packedOrdersMemory = _packedOrdersByStrategyId[strategyId];
            (Order[2] memory orders, bool ordersInverted) = _unpackOrders(packedOrdersMemory);

            _validateTradeParams(pair.id, strategyId, amount);

            Order memory targetOrder = isTargetToken0 == ordersInverted ? orders[1] : orders[0];

            // calculate the orders new values
            (uint128 sourceAmount, uint128 targetAmount) = _singleTradeActionSourceAndTargetAmounts(
                targetOrder,
                amount,
                byTargetAmount
            );

            // update totals
            totals.sourceAmount += sourceAmount;
            totals.targetAmount += targetAmount;
        }

        // apply trading fee
        if (byTargetAmount) {
            totals.sourceAmount = _addFee(totals.sourceAmount, pair.id);
        } else {
            totals.targetAmount = _subtractFee(totals.targetAmount, pair.id);
        }
    }

    /**
     * @dev returns stored strategies of a pair
     */
    function _strategiesByPair(
        Pair memory pair,
        uint256 startIndex,
        uint256 endIndex,
        IVoucher voucher
    ) internal view returns (Strategy[] memory) {
        EnumerableSetUpgradeable.UintSet storage strategyIds = _strategyIdsByPairIdStorage[pair.id];
        uint256 allLength = strategyIds.length();

        // when the endIndex is 0 or out of bound, set the endIndex to the last value possible
        if (endIndex == 0 || endIndex > allLength) {
            endIndex = allLength;
        }

        // revert when startIndex is out of bound
        if (startIndex > endIndex) {
            revert InvalidIndices();
        }

        // populate the result
        uint256 resultLength = endIndex - startIndex;
        Strategy[] memory result = new Strategy[](resultLength);
        for (uint256 i = 0; i < resultLength; i = uncheckedInc(i)) {
            uint256 strategyId = strategyIds.at(startIndex + i);
            result[i] = _strategy(strategyId, voucher, pair);
        }

        return result;
    }

    /**
     * @dev returns the count of stored strategies of a pair
     */
    function _strategiesByPairCount(Pair memory pair) internal view returns (uint256) {
        EnumerableSetUpgradeable.UintSet storage strategyIds = _strategyIdsByPairIdStorage[pair.id];
        return strategyIds.length();
    }

    /**
     @dev returns a strategy object matching the provided id.
     */
    function _strategy(uint256 id, IVoucher voucher, Pair memory pair) internal view returns (Strategy memory) {
        // fetch data
        address _owner = voucher.ownerOf(id);
        uint256[3] memory packedOrdersMemory = _packedOrdersByStrategyId[id];
        (Order[2] memory orders, bool ordersInverted) = _unpackOrders(packedOrdersMemory);

        // handle sorting
        Token[2] memory sortedTokens = _sortStrategyTokens(pair, ordersInverted);

        return Strategy({ id: id, owner: _owner, tokens: sortedTokens, orders: orders });
    }

    /**
     * @dev validates deposit amounts, refunds excess native tokens sent
     */
    function _validateDepositAndRefundExcessNativeToken(
        Token token,
        address owner,
        uint256 depositAmount,
        uint256 txValue,
        bool validateDepositAmount
    ) private {
        if (token.isNative()) {
            if (txValue < depositAmount) {
                revert NativeAmountMismatch();
            }

            // refund the owner for the remaining native token amount
            if (txValue > depositAmount) {
                payable(address(owner)).sendValue(txValue - depositAmount);
            }
        } else if (depositAmount > 0) {
            if (validateDepositAmount) {
                uint256 prevBalance = token.balanceOf(address(this));
                token.safeTransferFrom(owner, address(this), depositAmount);
                uint256 newBalance = token.balanceOf(address(this));
                if (newBalance - prevBalance != depositAmount) {
                    revert BalanceMismatch();
                }
            } else {
                token.safeTransferFrom(owner, address(this), depositAmount);
            }
        }
    }

    function _validateTradeParams(uint128 pairId, uint256 strategyId, uint128 tradeAmount) private pure {
        // make sure the strategy id matches the pair id
        if (_pairIdByStrategyId(strategyId) != pairId) {
            revert InvalidTradeActionStrategyId();
        }

        // make sure the trade amount is nonzero
        if (tradeAmount == 0) {
            revert InvalidTradeActionAmount();
        }
    }

    /**
     * @dev sets the trading fee (in units of PPM)
     */
    function _setTradingFeePPM(uint32 newTradingFeePPM) internal {
        uint32 prevTradingFeePPM = _tradingFeePPM;
        if (prevTradingFeePPM == newTradingFeePPM) {
            return;
        }

        _tradingFeePPM = newTradingFeePPM;

        emit TradingFeePPMUpdated({ prevFeePPM: prevTradingFeePPM, newFeePPM: newTradingFeePPM });
    }

    /**
     * @dev sets the custom trading fee for a given pair (in units of PPM)
     */
    function _setPairTradingFeePPM(Pair memory pair, uint32 newCustomTradingFeePPM) internal {
        uint32 prevCustomTradingFeePPM = _customTradingFeePPM[pair.id];
        if (prevCustomTradingFeePPM == newCustomTradingFeePPM) {
            return;
        }

        _customTradingFeePPM[pair.id] = newCustomTradingFeePPM;

        emit PairTradingFeePPMUpdated({
            token0: pair.tokens[0],
            token1: pair.tokens[1],
            prevFeePPM: prevCustomTradingFeePPM,
            newFeePPM: newCustomTradingFeePPM
        });
    }

    /**
     * returns true if the provided orders are equal, false otherwise
     */
    function _equalStrategyOrders(Order[2] memory orders0, Order[2] memory orders1) internal pure returns (bool) {
        uint256 i;
        for (i = 0; i < 2; i = uncheckedInc(i)) {
            if (
                orders0[i].y != orders1[i].y ||
                orders0[i].z != orders1[i].z ||
                orders0[i].A != orders1[i].A ||
                orders0[i].B != orders1[i].B
            ) {
                return false;
            }
        }
        return true;
    }

    // solhint-disable var-name-mixedcase

    /**
     * @dev returns:
     *
     *      x * (A * y + B * z) ^ 2
     * ---------------------------------
     *  A * x * (A * y + B * z) + z ^ 2
     *
     */
    function _calculateTradeTargetAmount(
        uint256 x, // < 2 ^ 128
        uint256 y, // < 2 ^ 128
        uint256 z, // < 2 ^ 128
        uint256 A, // < 2 ^ 96
        uint256 B /// < 2 ^ 96
    ) private pure returns (uint256) {
        if (A == 0) {
            if (B == 0) {
                revert OrderDisabled();
            }
            return MathEx.mulDivF(x, B * B, ONE * ONE);
        }

        uint256 temp1;
        uint256 temp2;
        unchecked {
            temp1 = z * ONE; // < 2 ^ 176
            temp2 = y * A + z * B; // < 2 ^ 225
        }
        uint256 temp3 = temp2 * x;

        uint256 factor1 = MathEx.minFactor(temp1, temp1);
        uint256 factor2 = MathEx.minFactor(temp3, A);
        uint256 factor = MathUpgradeable.max(factor1, factor2);

        uint256 temp4 = MathEx.mulDivC(temp1, temp1, factor);
        uint256 temp5 = MathEx.mulDivC(temp3, A, factor);
        return MathEx.mulDivF(temp2, temp3 / factor, temp4 + temp5);
    }

    /**
     * @dev returns:
     *
     *                  x * z ^ 2
     * -------------------------------------------
     *  (A * y + B * z) * (A * y + B * z - A * x)
     *
     */
    function _calculateTradeSourceAmount(
        uint256 x, // < 2 ^ 128
        uint256 y, // < 2 ^ 128
        uint256 z, // < 2 ^ 128
        uint256 A, // < 2 ^ 96
        uint256 B /// < 2 ^ 96
    ) private pure returns (uint256) {
        if (A == 0) {
            if (B == 0) {
                revert OrderDisabled();
            }
            return MathEx.mulDivC(x, ONE * ONE, B * B);
        }

        uint256 temp1;
        uint256 temp2;
        unchecked {
            temp1 = z * ONE; // < 2 ^ 176
            temp2 = y * A + z * B; // < 2 ^ 225
        }
        uint256 temp3 = temp2 - x * A;

        uint256 factor1 = MathEx.minFactor(temp1, temp1);
        uint256 factor2 = MathEx.minFactor(temp2, temp3);
        uint256 factor = MathUpgradeable.max(factor1, factor2);

        uint256 temp4 = MathEx.mulDivC(temp1, temp1, factor);
        uint256 temp5 = MathEx.mulDivF(temp2, temp3, factor);
        return MathEx.mulDivC(x, temp4, temp5);
    }

    // solhint-enable var-name-mixedcase

    /**
     * @dev pack 2 orders into a 3 slot uint256 data structure
     */
    function _packOrders(Order[2] memory orders, bool ordersInverted) private pure returns (uint256[3] memory values) {
        values = [
            uint256((uint256(orders[0].y) << 0) | (uint256(orders[1].y) << 128)),
            uint256((uint256(orders[0].z) << 0) | (uint256(orders[0].A) << 128) | (uint256(orders[0].B) << 192)),
            uint256(
                (uint256(orders[1].z) << 0) |
                    (uint256(orders[1].A) << 128) |
                    (uint256(orders[1].B) << 192) |
                    (ordersInverted ? ORDERS_INVERTED_FLAG : 0)
            )
        ];
    }

    /**
     * @dev unpack 2 stored orders into an array of Order types
     */
    function _unpackOrders(
        uint256[3] memory values
    ) private pure returns (Order[2] memory orders, bool ordersInverted) {
        orders = [
            Order({
                y: uint128(values[0] >> 0),
                z: uint128(values[1] >> 0),
                A: uint64(values[1] >> 128),
                B: uint64(values[1] >> 192)
            }),
            Order({
                y: uint128(values[0] >> 128),
                z: uint128(values[2] >> 0),
                A: uint64(values[2] >> 128),
                B: uint64((values[2] << 1) >> 193)
            })
        ];
        ordersInverted = values[2] >= ORDERS_INVERTED_FLAG;
    }

    /**
     * @dev expand a given rate
     */
    function _expandRate(uint256 rate) internal pure returns (uint256) {
        // safe because no `+` or `-` or `*`
        unchecked {
            return (rate % ONE) << (rate / ONE);
        }
    }

    /**
     * @dev validates a given rate
     */
    function _validRate(uint256 rate) internal pure returns (bool) {
        // safe because no `+` or `-` or `*`
        unchecked {
            return (ONE >> (rate / ONE)) > 0;
        }
    }

    /**
     * @dev returns the source and target amounts of a single trade action
     */
    function _singleTradeActionSourceAndTargetAmounts(
        Order memory order,
        uint128 amount,
        bool byTargetAmount
    ) internal pure returns (uint128 sourceAmount, uint128 targetAmount) {
        uint256 y = uint256(order.y);
        uint256 z = uint256(order.z);
        uint256 a = _expandRate(uint256(order.A));
        uint256 b = _expandRate(uint256(order.B));
        if (byTargetAmount) {
            sourceAmount = _calculateTradeSourceAmount(amount, y, z, a, b).toUint128();
            targetAmount = amount;
        } else {
            sourceAmount = amount;
            targetAmount = _calculateTradeTargetAmount(amount, y, z, a, b).toUint128();
        }
    }

    /**
     * revert if any of the orders is invalid
     */
    function _validateOrders(Order[2] calldata orders) internal pure {
        for (uint256 i = 0; i < 2; i = uncheckedInc(i)) {
            if (orders[i].z < orders[i].y) {
                revert InsufficientCapacity();
            }
            if (!_validRate(orders[i].A)) {
                revert InvalidRate();
            }
            if (!_validRate(orders[i].B)) {
                revert InvalidRate();
            }
        }
    }

    /**
     * returns the strategyId for a given pairId and a given strategyIndex
     */
    function _strategyId(uint128 pairId, uint128 strategyIndex) internal pure returns (uint256) {
        return (uint256(pairId) << 128) | strategyIndex;
    }

    /**
     * returns the pairId associated with a given strategyId
     */
    function _pairIdByStrategyId(uint256 strategyId) internal pure returns (uint128) {
        return uint128(strategyId >> 128);
    }

    function _withdrawFees(address sender, uint256 amount, Token token, address recipient) internal returns (uint256) {
        uint256 accumulatedAmount = _accumulatedFees[token];
        if (accumulatedAmount == 0) {
            return 0;
        }
        if (amount > accumulatedAmount) {
            amount = accumulatedAmount;
        }

        _accumulatedFees[token] = accumulatedAmount - amount;
        _withdrawFunds(token, payable(recipient), amount);
        emit FeesWithdrawn(token, recipient, amount, sender);
        return amount;
    }

    /**
     * returns tokens sorted accordingly to a strategy orders inversion
     */
    function _sortStrategyTokens(Pair memory pair, bool ordersInverted) private pure returns (Token[2] memory) {
        return ordersInverted ? [pair.tokens[1], pair.tokens[0]] : pair.tokens;
    }

    /**
     * sends erc20 or native token to the provided target
     */
    function _withdrawFunds(Token token, address payable target, uint256 amount) private {
        if (amount == 0) {
            return;
        }

        if (token.isNative()) {
            // using a regular transfer here would revert due to exceeding the 2300 gas limit which is why we're using
            // call instead (via sendValue), which the 2300 gas limit does not apply for
            target.sendValue(amount);
        } else {
            token.safeTransfer(target, amount);
        }
    }

    function uncheckedInc(uint256 i) private pure returns (uint256 j) {
        unchecked {
            j = i + 1;
        }
    }
}
