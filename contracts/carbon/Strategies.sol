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

// solhint-disable var-name-mixedcase
/**
 * @dev:
 *
 * a strategy consists of two orders:
 * - order 0 sells `y0` units of token 0 at a marginal rate of `M0` ranging between `L0` and `H0`
 * - order 1 sells `y1` units of token 1 at a marginal rate of `M1` ranging between `L1` and `H1`
 *
 * rate symbols:
 * - `L0` indicates the lowest value of one wei of token 0 in units of token 1
 * - `H0` indicates the highest value of one wei of token 0 in units of token 1
 * - `M0` indicates the marginal value of one wei of token 0 in units of token 1
 * - `L1` indicates the lowest value of one wei of token 1 in units of token 0
 * - `H1` indicates the highest value of one wei of token 1 in units of token 0
 * - `M1` indicates the marginal value of one wei of token 1 in units of token 0
 *
 * the term "one wei" serves here as a simplification of "an amount tending to zero"
 * hence the rate values above are all theoretical
 * moreover, an order doesn't actually hold these values
 * instead, it maintains a modified version of them, as explained below
 *
 * given:
 * - `min = floor(2^32 * sqrt(L))`
 * - `max = floor(2^32 * sqrt(H))`
 * - `mid = floor(2^32 * sqrt(M))`
 *
 * the order maintains:
 * - `y = current liquidity`
 * - `z = current liquidity * (max - min) / (mid - min)`
 * - `A = max - min`
 * - `B = min`
 *
 * the order reflects:
 * - `L = (B / 2^32) ^ 2`
 * - `H = ((B + A) / 2^32) ^ 2`
 * - `M = ((B + A * y / z) / 2^32) ^ 2`
 *
 * upon trading on a given order in a given strategy:
 * - the value of `y` in the given order decreases
 * - the value of `y` in the other order increases
 * - the value of `z` in the other order may increase
 * - the values of all other parameters remain unchanged
 *
 * given a source amount `x`, the expected target amount is:
 * - theoretical formula: `M * x * y / ((M - sqrt(M * L)) * x + y)`
 * - implemented formula: `x * (A * y + B * z) ^ 2 / (A * x * (A * y + B * z) + z ^ 2)`
 *
 * given a target amount `x`, the required source amount is:
 * - theoretical formula: `x * y / ((sqrt(M * L) - M) * x + M * y)`
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
    error StrategyDoesNotExist();
    error InvalidIndices();
    error InsufficientCapacity();

    struct StoredStrategy {
        uint256 id;
        address owner;
        Pair pair;
        uint256[3] packedOrders;
    }

    struct StorageUpdate {
        uint256 index;
        uint256 value;
    }

    struct StrategyUpdate {
        uint256 id;
        address owner;
        Token token0;
        Token token1;
        Order order0;
        Order order1;
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
    }

    struct TradeOrders {
        uint256[3] packedOrders;
        Order[2] orders;
    }

    uint256 private constant ONE = 1 << 32;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 1500; // 0.15%

    // unique incremental id representing a pool
    CountersUpgradeable.Counter private _lastStrategyId;

    // mapping between a strategyId to its Strategy object
    mapping(uint256 => StoredStrategy) private _strategiesStorage;

    // mapping between a pool id to its strategies ids
    mapping(uint256 => EnumerableSetUpgradeable.UintSet) private _strategiesByPoolIdStorage;

    // the global trading fee (in units of PPM)
    uint32 private _tradingFeePPM;

    // accumulated fees per token
    mapping(address => uint256) private _accumulatedFees;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 5] private __gap;

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
    event StrategyUpdated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

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
        _depositToMasterVaultAndRefundExcessNativeToken(masterVault, pair.token0, owner, orders[0].y, value);
        _depositToMasterVaultAndRefundExcessNativeToken(masterVault, pair.token1, owner, orders[1].y, value);

        _lastStrategyId.increment();
        uint256 id = _lastStrategyId.current();

        _strategiesByPoolIdStorage[pool.id].add(id);
        _strategiesStorage[id] = StoredStrategy({
            id: id,
            owner: owner,
            pair: pair,
            packedOrders: _packOrders(orders)
        });

        voucher.mint(owner, id);

        emit StrategyCreated({
            id: id,
            owner: owner,
            token0: pair.token0,
            token1: pair.token1,
            order0: orders[0],
            order1: orders[1]
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
        address owner,
        uint256 value
    ) internal {
        for (uint256 i = 0; i < 2; i++) {
            Token token = i == 0 ? strategy.pair.token0 : strategy.pair.token1;

            // handle transfers
            if (newOrders[i].y < strategy.orders[i].y) {
                // liquidity decreased - withdraw the difference
                uint128 delta = strategy.orders[i].y - newOrders[i].y;
                vault.withdrawFunds(token, payable(owner), delta);
            } else if (newOrders[i].y > strategy.orders[i].y) {
                // liquidity increased - deposit the difference
                uint128 delta = newOrders[i].y - strategy.orders[i].y;
                _depositToMasterVaultAndRefundExcessNativeToken(vault, token, owner, delta, value);
            }
        }

        // update storage
        _strategiesStorage[strategy.id].packedOrders = _packOrders(newOrders);

        // emit event
        emit StrategyUpdated({
            id: strategy.id,
            owner: owner,
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
        address owner,
        IMasterVault vault,
        Pool memory pool
    ) internal {
        // burn the voucher nft token
        voucher.burn(strategy.id);

        // clear storage
        delete _strategiesStorage[strategy.id];
        _strategiesByPoolIdStorage[pool.id].remove(strategy.id);

        // withdraw funds
        vault.withdrawFunds(strategy.pair.token0, payable(owner), strategy.orders[0].y);
        vault.withdrawFunds(strategy.pair.token1, payable(owner), strategy.orders[1].y);

        // emit event
        emit StrategyDeleted({
            id: strategy.id,
            owner: owner,
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
            StoredStrategy storage storedStrategy = _strategiesStorage[params.tradeActions[i].strategyId];
            TradeOrders memory tradeOrders = TradeOrders({
                packedOrders: storedStrategy.packedOrders,
                orders: _unpackOrders(storedStrategy.packedOrders)
            });

            // calculate the orders new values
            uint256 targetTokenIndex = _findTargetTokenIndex(storedStrategy, params.tokens);
            SourceAndTargetAmounts memory tempTradeAmounts = _singleTradeActionSourceAndTargetAmounts(
                tradeOrders.orders[targetTokenIndex],
                params.tradeActions[i],
                params.byTargetAmount
            );

            // update the orders with the new values
            _updateOrders(tradeOrders.orders, targetTokenIndex, tempTradeAmounts);

            // store new values if necessary
            uint256[3] memory newPackedOrders = _packOrders(tradeOrders.orders);
            bool strategyUpdated = false;
            for (uint256 n = 0; n < 3; n++) {
                if (tradeOrders.packedOrders[n] != newPackedOrders[n]) {
                    storedStrategy.packedOrders[n] = newPackedOrders[n];
                    strategyUpdated = true;
                }
            }

            // emit update events if necessary
            if (strategyUpdated) {
                emit StrategyUpdated({
                    id: storedStrategy.id,
                    owner: storedStrategy.owner,
                    token0: storedStrategy.pair.token0,
                    token1: storedStrategy.pair.token1,
                    order0: tradeOrders.orders[0],
                    order1: tradeOrders.orders[1]
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

        // revert here if the minReturn/maxInput constrants is unmet
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

        return SourceAndTargetAmounts({ sourceAmount: totals.sourceAmount, targetAmount: totals.targetAmount });
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
    function _findTargetTokenIndex(StoredStrategy memory strategy, TradeTokens memory tokens)
        private
        pure
        returns (uint256)
    {
        return tokens.target == strategy.pair.token0 ? 0 : 1;
    }

    /**
     * @dev calculates and returns the total source and target amounts of a trade, including fees
     */
    function _tradeSourceAndTargetAmounts(
        TradeTokens memory tokens,
        TradeAction[] calldata tradeActions,
        bool byTargetAmount
    ) internal view returns (SourceAndTargetAmounts memory) {
        SourceAndTargetAmounts memory totals = SourceAndTargetAmounts({ sourceAmount: 0, targetAmount: 0 });

        // process trade actions
        for (uint256 i = 0; i < tradeActions.length; i++) {
            // prepare variables
            StoredStrategy memory storedStrategy = _strategiesStorage[tradeActions[i].strategyId];
            Order[2] memory orders = _unpackOrders(storedStrategy.packedOrders);

            // calculate the orders new values
            uint256 targetTokenIndex = _findTargetTokenIndex(storedStrategy, tokens);

            SourceAndTargetAmounts memory tempTradeAmounts = _singleTradeActionSourceAndTargetAmounts(
                orders[targetTokenIndex],
                tradeActions[i],
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
        return SourceAndTargetAmounts({ sourceAmount: totals.sourceAmount, targetAmount: totals.targetAmount });
    }

    /**
     * @dev returns stored strategies matching provided strategyIds
     */
    function _strategiesByIds(uint256[] calldata strategyIds) internal view returns (Strategy[] memory) {
        uint256 length = strategyIds.length;
        Strategy[] memory result = new Strategy[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = _strategy(strategyIds[i]);
        }
        return result;
    }

    /**
     * @dev returns stored strategies of a pool
     */
    function _strategiesByPool(
        Pool memory pool,
        uint256 startIndex,
        uint256 endIndex
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
            result[i] = _strategy(strategyId);
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
    function _strategy(uint256 id) internal view returns (Strategy memory) {
        StoredStrategy memory strategy = _strategiesStorage[id];
        if (strategy.id <= 0) {
            revert StrategyDoesNotExist();
        }
        return
            Strategy({
                id: strategy.id,
                owner: strategy.owner,
                pair: strategy.pair,
                orders: _unpackOrders(strategy.packedOrders)
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

    /**
     * updates the owner of a strategy
     * note that this does not update the owner's voucher
     */
    function _updateStrategyOwner(Strategy memory strategy, address newOwner) internal {
        _strategiesStorage[strategy.id].owner = newOwner;
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
    function _tradeTargetAmount(uint256 x, Order memory order) private pure returns (uint128) {
        uint256 y = uint256(order.y);
        uint256 z = uint256(order.z);
        uint256 A = uint256(order.A);
        uint256 B = uint256(order.B);

        if (A == 0) {
            return MathEx.mulDivF(x, B * B, ONE * ONE).toUint128();
        }

        uint256 temp1 = y * A + z * B;
        uint256 temp2 = (temp1 * x) / ONE;
        uint256 temp3 = temp2 * A + z * z * ONE;
        return MathEx.mulDivF(temp1, temp2, temp3).toUint128();
    }

    /**
     * @dev returns:
     *
     *                  x * z ^ 2
     * -------------------------------------------
     *  (A * y + B * z) * (A * y + B * z - A * x)
     *
     */
    function _tradeSourceAmount(uint256 x, Order memory order) private pure returns (uint128) {
        uint256 y = uint256(order.y);
        uint256 z = uint256(order.z);
        uint256 A = uint256(order.A);
        uint256 B = uint256(order.B);

        if (A == 0) {
            return MathEx.mulDivC(x, ONE * ONE, B * B).toUint128();
        }

        uint256 temp1 = z * ONE;
        uint256 temp2 = y * A + z * B;
        uint256 temp3 = temp2 - x * A;
        return MathEx.mulDivC(x * temp1, temp1, temp2 * temp3).toUint128();
    }

    // solhint-enable var-name-mixedcase

    /**
     * @dev pack 2 orders into a 3 slot uint256 data structure
     */
    function _packOrders(Order[2] memory orders) private pure returns (uint256[3] memory) {
        return [
            uint256((uint256(orders[0].y) << 0) | (uint256(orders[1].y) << 128)),
            uint256((uint256(orders[0].z) << 0) | (uint256(orders[0].A) << 128) | (uint256(orders[0].B) << 192)),
            uint256((uint256(orders[1].z) << 0) | (uint256(orders[1].A) << 128) | (uint256(orders[1].B) << 192))
        ];
    }

    /**
     * @dev unpack 2 stored orders into an array of Order types
     */
    function _unpackOrders(uint256[3] memory values) private pure returns (Order[2] memory) {
        return [
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
                B: uint64(values[2] >> 192)
            })
        ];
    }

    /**
     * @dev returns the source and target amounts of a single trade action
     */
    function _singleTradeActionSourceAndTargetAmounts(
        Order memory order,
        TradeAction memory action,
        bool byTargetAmount
    ) private pure returns (SourceAndTargetAmounts memory) {
        SourceAndTargetAmounts memory amounts = SourceAndTargetAmounts({ sourceAmount: 0, targetAmount: 0 });
        if (byTargetAmount) {
            amounts.sourceAmount = _tradeSourceAmount(action.amount, order);
            amounts.targetAmount = action.amount;
        } else {
            amounts.sourceAmount = action.amount;
            amounts.targetAmount = _tradeTargetAmount(action.amount, order);
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
     * reverts if the capacity isn't greater or equal to the liquidity
     */
    function _validateSufficientCapacity(Order[2] calldata orders) internal pure {
        for (uint256 i = 0; i < 2; i++) {
            if (orders[i].z < orders[i].y) {
                revert InsufficientCapacity();
            }
        }
    }
}
