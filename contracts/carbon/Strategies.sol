// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { MathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { MathEx } from "../utility/MathEx.sol";
import { Token } from "../token/Token.sol";
import { TokenLibrary } from "../token/TokenLibrary.sol";
import { Pool } from "./Pools.sol";
import { IMasterVault } from "../vaults/interfaces/IMasterVault.sol";
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

struct Pair {
    Token token0;
    Token token1;
}

struct TradeTokens {
    Token source;
    Token target;
}

struct Strategy {
    uint256 id;
    address owner;
    Pair pair;
    Order[2] orders;
    bool ordersInverted;
}

struct TradeAction {
    uint256 strategyId;
    uint128 amount;
}

abstract contract Strategies is Initializable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using TokenLibrary for Token;
    using Address for address payable;
    using MathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;

    error NativeAmountMismatch();
    error GreaterThanMaxInput();
    error LowerThanMinReturn();
    error InvalidIndices();
    error InsufficientCapacity();
    error InvalidRate();
    error InsufficientLiquidity();
    error TokensMismatch();
    error StrategyDoesNotExist();

    struct StoredStrategy {
        address owner;
        Pair pair;
        uint256[3] packedOrders;
    }

    struct StorageUpdate {
        uint256 index;
        uint256 value;
    }

    struct SourceAndTargetAmounts {
        uint128 sourceAmount;
        uint128 targetAmount;
    }

    struct TradeParams {
        address trader;
        TradeTokens tokens;
        TradeAction[] tradeActions;
        bool byTargetAmount;
        IMasterVault masterVault;
        uint128 constraint;
        uint256 txValue;
        Pool pool;
    }

    struct TradeOrders {
        uint256[3] packedOrders;
        Order[2] orders;
    }

    uint256 private constant ONE = 1 << 48;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 1500; // 0.15%

    // unique incremental id representing a pool
    CountersUpgradeable.Counter private _lastStrategyId;

    // mapping between a strategy to its packed orders
    mapping(uint256 => uint256[3]) private _packedOrdersByStrategyId;

    // mapping between strategy to its pool
    mapping(uint256 => uint256) private __poolIdbyStrategyId;

    // mapping between a pool id to its strategies ids
    mapping(uint256 => EnumerableSetUpgradeable.UintSet) private _strategiesByPoolIdStorage;

    // the global trading fee (in units of PPM)
    uint32 private _tradingFeePPM;

    // accumulated fees per token
    mapping(address => uint256) private _accumulatedFees;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 6] private __gap;

    /**
     * @dev triggered when the network fee is updated
     */
    event TradingFeePPMUpdated(uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev emits following a pool's creation
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
     * @dev emits following a pool's creation
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
     * @dev emits following an update to either or both of the orders
     */
    event StrategyUpdated(uint256 indexed id, Token indexed token0, Token indexed token1, Order order0, Order order1);

    /**
     * @dev emits following a user initiated trade
     */
    event TokensTraded(
        address indexed trader,
        address indexed sourceToken,
        address indexed targetToken,
        uint256 sourceAmount,
        uint256 targetAmount,
        uint128 tradingFeeAmount,
        bool byTargetAmount
    );

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
        IMasterVault masterVault,
        IVoucher voucher,
        Pair memory pair,
        Order[2] calldata orders,
        Pool memory pool,
        address owner,
        uint256 value
    ) internal returns (uint256) {
        // sort orders
        bool ordersInverted = pair.token0 == pool.token1;
        Order[2] memory sortedOrders = ordersInverted ? [orders[1], orders[0]] : orders;

        _depositToMasterVaultAndRefundExcessNativeToken(masterVault, pool.token0, owner, sortedOrders[0].y, value);
        _depositToMasterVaultAndRefundExcessNativeToken(masterVault, pool.token1, owner, sortedOrders[1].y, value);

        _lastStrategyId.increment();
        uint256 id = _lastStrategyId.current();

        _strategiesByPoolIdStorage[pool.id].add(id);
        _packedOrdersByStrategyId[id] = _packOrders(sortedOrders, ordersInverted);
        __poolIdbyStrategyId[id] = pool.id;

        voucher.mint(owner, id);

        emit StrategyCreated({
            id: id,
            owner: owner,
            token0: pool.token0,
            token1: pool.token1,
            order0: sortedOrders[0],
            order1: sortedOrders[1]
        });

        return id;
    }

    /**
     * @dev updates an existing strategy
     */
    function _updateStrategy(
        IMasterVault vault,
        Strategy memory strategy,
        Order[2] calldata newOrders,
        uint256 value
    ) internal {
        // prepare storage variable
        uint256[3] storage packedOrders = _packedOrdersByStrategyId[strategy.id];
        (Order[2] memory orders, bool ordersInverted) = _unpackOrders(packedOrders);

        // store new values if necessary
        uint256[3] memory newPackedOrders = _packOrders(newOrders, ordersInverted);
        for (uint256 n = 0; n < 3; n++) {
            if (packedOrders[n] != newPackedOrders[n]) {
                packedOrders[n] = newPackedOrders[n];
            }
        }

        // deposit and withdraw
        for (uint256 i = 0; i < 2; i++) {
            Token token = i == 0 ? strategy.pair.token0 : strategy.pair.token1;

            if (newOrders[i].y < orders[i].y) {
                // liquidity decreased - withdraw the difference
                uint128 delta = orders[i].y - newOrders[i].y;
                vault.withdrawFunds(token, payable(strategy.owner), delta);
            } else if (newOrders[i].y > orders[i].y) {
                // liquidity increased - deposit the difference
                uint128 delta = newOrders[i].y - orders[i].y;
                _depositToMasterVaultAndRefundExcessNativeToken(vault, token, strategy.owner, delta, value);
            }
        }

        // emit event
        emit StrategyUpdated({
            id: strategy.id,
            token0: strategy.pair.token0,
            token1: strategy.pair.token1,
            order0: newOrders[0],
            order1: newOrders[1]
        });
    }

    /**
     * @dev deletes a strategy
     */
    function _deleteStrategy(
        Strategy memory strategy,
        IVoucher voucher,
        IMasterVault vault,
        Pool memory pool
    ) internal {
        // burn the voucher nft token
        voucher.burn(strategy.id);

        // clear storage
        delete _packedOrdersByStrategyId[strategy.id];
        delete __poolIdbyStrategyId[strategy.id];
        _strategiesByPoolIdStorage[pool.id].remove(strategy.id);

        // withdraw funds
        vault.withdrawFunds(strategy.pair.token0, payable(strategy.owner), strategy.orders[0].y);
        vault.withdrawFunds(strategy.pair.token1, payable(strategy.owner), strategy.orders[1].y);

        // emit event
        emit StrategyDeleted({
            id: strategy.id,
            owner: strategy.owner,
            token0: strategy.pair.token0,
            token1: strategy.pair.token1,
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
    function _trade(TradeParams memory params) internal returns (SourceAndTargetAmounts memory) {
        SourceAndTargetAmounts memory totals = SourceAndTargetAmounts({ sourceAmount: 0, targetAmount: 0 });

        // process trade actions
        for (uint256 i = 0; i < params.tradeActions.length; i++) {
            // prepare variables
            uint256 strategyId = params.tradeActions[i].strategyId;
            uint256[3] storage packedOrders = _packedOrdersByStrategyId[strategyId];
            (Order[2] memory orders, bool ordersInverted) = _unpackOrders(packedOrders);

            // make sure strategyIds match the provided source/target tokens
            if (_poolIdbyStrategyId(strategyId) != params.pool.id) {
                revert TokensMismatch();
            }

            // calculate the orders new values
            uint256 targetTokenIndex = _findTargetTokenIndex(params.pool, params.tokens);
            SourceAndTargetAmounts memory tempTradeAmounts = _singleTradeActionSourceAndTargetAmounts(
                orders[targetTokenIndex],
                params.tradeActions[i].amount,
                params.byTargetAmount
            );

            // update the orders with the new values
            _updateOrders(orders, targetTokenIndex, tempTradeAmounts);

            // store new values if necessary
            uint256[3] memory newPackedOrders = _packOrders(orders, ordersInverted);
            bool strategyUpdated = false;
            for (uint256 n = 0; n < 3; n++) {
                if (packedOrders[n] != newPackedOrders[n]) {
                    packedOrders[n] = newPackedOrders[n];
                    strategyUpdated = true;
                }
            }

            // emit update events if necessary
            if (strategyUpdated) {
                emit StrategyUpdated({
                    id: strategyId,
                    token0: params.pool.token0,
                    token1: params.pool.token1,
                    order0: orders[0],
                    order1: orders[1]
                });
            }

            totals.sourceAmount += tempTradeAmounts.sourceAmount;
            totals.targetAmount += tempTradeAmounts.targetAmount;
        }

        // apply trading fee
        uint128 tradingFeeAmount;
        address tradingFeeToken;
        if (params.byTargetAmount) {
            uint128 amountIncludingFee = _addFee(totals.sourceAmount);
            tradingFeeAmount = amountIncludingFee - totals.sourceAmount;
            tradingFeeToken = address(params.tokens.source);
            totals.sourceAmount = amountIncludingFee;
        } else {
            uint128 amountIncludingFee = _subtractFee(totals.targetAmount);
            tradingFeeAmount = totals.targetAmount - amountIncludingFee;
            tradingFeeToken = address(params.tokens.target);
            totals.targetAmount = amountIncludingFee;
        }

        // revert here if the minReturn/maxInput constraints are unmet
        _validateConstraints(params.byTargetAmount, totals, params.constraint);

        // transfer funds
        _depositToMasterVaultAndRefundExcessNativeToken(
            params.masterVault,
            params.tokens.source,
            params.trader,
            totals.sourceAmount,
            params.txValue
        );
        params.masterVault.withdrawFunds(params.tokens.target, payable(params.trader), totals.targetAmount);

        // update fee counters
        _accumulatedFees[tradingFeeToken] += tradingFeeAmount;

        // tokens traded sucesfully, emit event
        emit TokensTraded({
            trader: params.trader,
            sourceToken: address(params.tokens.source),
            targetToken: address(params.tokens.target),
            sourceAmount: totals.sourceAmount,
            targetAmount: totals.targetAmount,
            tradingFeeAmount: tradingFeeAmount,
            byTargetAmount: params.byTargetAmount
        });

        return totals;
    }

    /**
     * @dev calculates the required amount plus fee
     */
    function _addFee(uint128 amount) private view returns (uint128) {
        // divide the input amount by `1 - fee`
        return MathEx.mulDivC(amount, PPM_RESOLUTION, PPM_RESOLUTION - _tradingFeePPM).toUint128();
    }

    /**
     * @dev calculates the expected amount minus fee
     */
    function _subtractFee(uint128 amount) private view returns (uint128) {
        // multiply the input amount by `1 - fee`
        return MathEx.mulDivF(amount, PPM_RESOLUTION - _tradingFeePPM, PPM_RESOLUTION).toUint128();
    }

    /**
     * @dev validates the minReturn/maxInput constraints
     */
    function _validateConstraints(
        bool byTargetAmount,
        SourceAndTargetAmounts memory totals,
        uint128 constraint
    ) private pure {
        if (byTargetAmount) {
            // the source amount required is greater than maxInput
            if (totals.sourceAmount > constraint) {
                revert GreaterThanMaxInput();
            }
        } else {
            // the target amount is lower than minReturn
            if (totals.targetAmount < constraint) {
                revert LowerThanMinReturn();
            }
        }
    }

    /**
     * @dev returns the index of a trade's target token in a strategy
     */
    function _findTargetTokenIndex(Pool memory pool, TradeTokens memory tokens) private pure returns (uint256) {
        return tokens.target == pool.token0 ? 0 : 1;
    }

    /**
     * @dev calculates and returns the total source and target amounts of a trade, including fees
     */
    function _tradeSourceAndTargetAmounts(
        TradeTokens memory tokens,
        TradeAction[] calldata tradeActions,
        Pool memory pool,
        bool byTargetAmount
    ) internal view returns (SourceAndTargetAmounts memory) {
        SourceAndTargetAmounts memory totals = SourceAndTargetAmounts({ sourceAmount: 0, targetAmount: 0 });

        // process trade actions
        for (uint256 i = 0; i < tradeActions.length; i++) {
            // prepare variables
            uint256[3] storage packedOrders = _packedOrdersByStrategyId[tradeActions[i].strategyId];
            (Order[2] memory orders, ) = _unpackOrders(packedOrders);

            // calculate the orders new values
            uint256 targetTokenIndex = _findTargetTokenIndex(pool, tokens);

            SourceAndTargetAmounts memory tempTradeAmounts = _singleTradeActionSourceAndTargetAmounts(
                orders[targetTokenIndex],
                tradeActions[i].amount,
                byTargetAmount
            );

            // update totals
            totals.sourceAmount += tempTradeAmounts.sourceAmount;
            totals.targetAmount += tempTradeAmounts.targetAmount;
        }

        // apply trading fee
        if (byTargetAmount) {
            totals.sourceAmount = _addFee(totals.sourceAmount);
        } else {
            totals.targetAmount = _subtractFee(totals.targetAmount);
        }

        // return amounts
        return totals;
    }

    /**
     * @dev returns stored strategies of a pool
     */
    function _strategiesByPool(
        Pool memory pool,
        uint256 startIndex,
        uint256 endIndex,
        IVoucher voucher
    ) internal view returns (Strategy[] memory) {
        EnumerableSetUpgradeable.UintSet storage strategyIds = _strategiesByPoolIdStorage[pool.id];
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
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 strategyId = strategyIds.at(startIndex + i);
            result[i] = _strategy(strategyId, voucher, pool);
        }

        return result;
    }

    /**
     * @dev returns the count of stored strategies of a pool
     */
    function _strategiesByPoolCount(Pool memory pool) internal view returns (uint256) {
        EnumerableSetUpgradeable.UintSet storage strategyIds = _strategiesByPoolIdStorage[pool.id];
        return strategyIds.length();
    }

    /**
     @dev retuns a strategy object matching the provided id
     */
    function _strategy(uint256 id, IVoucher voucher, Pool memory pool) internal view returns (Strategy memory) {
        address _owner = voucher.ownerOf(id);

        uint256[3] storage packedOrders = _packedOrdersByStrategyId[id];
        (Order[2] memory _orders, bool ordersInverted) = _unpackOrders(packedOrders);

        return
            Strategy({
                id: id,
                owner: _owner,
                pair: Pair({ token0: pool.token0, token1: pool.token1 }),
                orders: _orders,
                ordersInverted: ordersInverted
            });
    }

    /**
     * @dev deposits tokens to the master vault, refunds excess native tokens sent
     */
    function _depositToMasterVaultAndRefundExcessNativeToken(
        IMasterVault masterVault,
        Token token,
        address owner,
        uint256 depositAmount,
        uint256 txValue
    ) internal {
        if (depositAmount == 0) {
            return;
        }

        if (token.isNative()) {
            if (txValue < depositAmount) {
                revert NativeAmountMismatch();
            }

            // using a regular transfer here would revert due to exceeding the 2300 gas limit which is why we're using
            // call instead (via sendValue), which the 2300 gas limit does not apply for
            payable(address(masterVault)).sendValue(depositAmount);

            // refund the owner for the remaining native token amount
            if (txValue > depositAmount) {
                payable(address(owner)).sendValue(txValue - depositAmount);
            }
        } else {
            token.safeTransferFrom(owner, address(masterVault), depositAmount);
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
     * returns the current trading fee
     */
    function _currentTradingFeePPM() internal view returns (uint32) {
        return _tradingFeePPM;
    }

    /**
     * returns the current amount of accumulated fees for a specific token
     */
    function _getAccumulatedFees(address token) internal view returns (uint256) {
        return _accumulatedFees[token];
    }

    /**
     * returns true if the provided orders are equal, false otherwise
     */
    function _equalStrategyOrders(Order[2] memory orders0, Order[2] memory orders1) internal pure returns (bool) {
        uint256 i;
        for (i = 0; i < 2; i++) {
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
        uint256 x,
        uint256 y,
        uint256 z,
        uint256 A,
        uint256 B
    ) private pure returns (uint256) {
        if (A == 0) {
            return MathEx.mulDivF(x, B * B, ONE * ONE);
        }

        uint256 temp1 = z * ONE;
        uint256 temp2 = y * A + z * B;
        uint256 temp3 = temp2 * x;

        uint256 factor1 = MathEx.mulDivC(temp1, temp1, type(uint256).max);
        uint256 factor2 = MathEx.mulDivC(temp3, A, type(uint256).max);
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
        uint256 x,
        uint256 y,
        uint256 z,
        uint256 A,
        uint256 B
    ) private pure returns (uint256) {
        if (A == 0) {
            return MathEx.mulDivC(x, ONE * ONE, B * B);
        }

        uint256 temp1 = z * ONE;
        uint256 temp2 = y * A + z * B;
        uint256 temp3 = temp2 - x * A;

        uint256 factor1 = MathEx.mulDivC(temp1, temp1, type(uint256).max);
        uint256 factor2 = MathEx.mulDivC(temp2, temp3, type(uint256).max);
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
                    (booleanToNumber(ordersInverted) << 255)
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
        ordersInverted = numberToBoolean(values[2] >> 255);
    }

    /**
     * @dev expand a given rate
     */
    function _expandRate(uint256 rate) private pure returns (uint256) {
        return (rate % ONE) << (rate / ONE);
    }

    /**
     * @dev validates a given rate
     */
    function _validRate(uint256 rate) private pure returns (bool) {
        return (ONE >> (rate / ONE)) > 0;
    }

    /**
     * @dev returns the source and target amounts of a single trade action
     */
    function _singleTradeActionSourceAndTargetAmounts(
        Order memory order,
        uint128 amount,
        bool byTargetAmount
    ) internal pure returns (SourceAndTargetAmounts memory) {
        SourceAndTargetAmounts memory amounts = SourceAndTargetAmounts({ sourceAmount: 0, targetAmount: 0 });
        uint256 y = uint256(order.y);
        uint256 z = uint256(order.z);
        uint256 a = _expandRate(uint256(order.A));
        uint256 b = _expandRate(uint256(order.B));
        if (byTargetAmount) {
            amounts.sourceAmount = _calculateTradeSourceAmount(amount, y, z, a, b).toUint128();
            amounts.targetAmount = amount;
        } else {
            amounts.sourceAmount = amount;
            amounts.targetAmount = _calculateTradeTargetAmount(amount, y, z, a, b).toUint128();
        }
        return amounts;
    }

    /**
     * @dev update order's according to a single trade action
     */
    function _updateOrders(
        Order[2] memory orders,
        uint256 targetTokenIndex,
        SourceAndTargetAmounts memory amounts
    ) private pure returns (Order[2] memory) {
        uint256 sourceTokenIndex = 1 - targetTokenIndex;
        orders[targetTokenIndex].y -= amounts.targetAmount;
        orders[sourceTokenIndex].y += amounts.sourceAmount;

        // when marginal and highest rate are equal
        if (orders[sourceTokenIndex].z < orders[sourceTokenIndex].y) {
            orders[sourceTokenIndex].z = orders[sourceTokenIndex].y;
        }
        return orders;
    }

    /**
     * revert if any of the orders is invalid
     */
    function _validateOrders(Order[2] calldata orders) internal pure {
        for (uint256 i = 0; i < 2; i++) {
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
     * returns the poolId relates to a given strategyId
     */
    function _poolIdbyStrategyId(uint256 strategyId) internal view returns (uint256) {
        uint256 id = __poolIdbyStrategyId[strategyId];
        if (id == 0) {
            revert StrategyDoesNotExist();
        }

        return id;
    }

    /**
     * returns a number representation for a boolean
     */
    function booleanToNumber(bool b) private pure returns (uint256) {
        return b ? 1 : 0;
    }

    /**
     * returns a boolean representation for a number
     */
    function numberToBoolean(uint256 u) private pure returns (bool) {
        return u == 1;
    }
}
