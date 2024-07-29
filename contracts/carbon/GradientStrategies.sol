// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MathEx } from "../utility/MathEx.sol";
import { InvalidIndices } from "../utility/Utils.sol";
import { Token } from "../token/Token.sol";
import { Pair } from "./Pairs.sol";
import { DecayMath } from "../utility/DecayMath.sol";
import { IVoucher } from "../voucher/interfaces/IVoucher.sol";
import { PPM_RESOLUTION } from "../utility/Constants.sol";
import { MAX_GAP } from "../utility/Constants.sol";
import { notEqual } from "../utility/Curve.sol";

/**
 * @dev:
 *
 * a strategy consists of one order:
 * - the order sells `x` units of targetToken (const) for `y` units of sourceToken (not const) at price { p0 : p1 }
 * - the price decays with time according to a decay formula defined by the user
 * - once the halflife time passes, the price is half of the initial price
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

enum GradientCurveTypes {
    LINEAR,
    EXPONENTIAL
}

struct Price {
    uint128 sourceAmount;
    uint128 targetAmount;
}

struct GradientOrder {
    Price initialPrice;
    Price endPrice;
    uint128 sourceAmount;
    uint128 targetAmount;
    uint32 tradingStartTime;
    uint32 expiry;
    bool tokensInverted;
    GradientCurve curve;
}

struct GradientStrategy {
    uint256 id;
    address owner;
    Token[2] tokens;
    GradientOrder order;
}

struct GradientCurve {
    GradientCurveTypes curveType;
    uint128 increaseAmount;
    uint32 increaseInterval;
    uint32 halflife;
    bool isDutchAuction;
}

struct TradeTokens {
    Token source;
    Token target;
}

struct TradeAction {
    uint256 strategyId;
    uint128 amount;
}

// strategy update reasons
uint8 constant STRATEGY_UPDATE_REASON_EDIT = 0;
uint8 constant STRATEGY_UPDATE_REASON_TRADE = 1;

abstract contract GradientStrategies is Initializable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using Address for address payable;
    using SafeCastUpgradeable for uint256;

    error NativeAmountMismatch();
    error BalanceMismatch();
    error GreaterThanMaxInput();
    error LowerThanMinReturn();
    error InsufficientCapacity();
    error InsufficientLiquidity();
    error InvalidRate();
    error InvalidTradeActionStrategyId();
    error InvalidTradeActionSourceToken();
    error InvalidTradeActionAmount();
    error InvalidOrderCurve();
    error InvalidOrderInitialPrice();
    error InvalidOrderEndPrice();
    error InvalidOrderTargetAmount();
    error InvalidExpiry();
    error OrderDisabled();
    error OrderExpired();
    error OutDated();
    error InvalidPrice();

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

    uint256 private constant MSB_MASK = uint256(1) << 255;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 4000; // 0.4%

    uint32 private constant DEFAULT_EXPIRY = 365 days;

    // total number of strategies
    uint128 private _strategyCounter;

    // the global trading fee (in units of PPM)
    uint32 internal _tradingFeePPM;

    // mapping between a gradient strategy id to its order
    mapping(uint256 => GradientOrder) private _gradientOrderByStrategyId;

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
     * @dev triggered when a gradient strategy is created
     */
    event StrategyCreated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        GradientOrder order
    );

    /**
     * @dev triggered when a gradient strategy is deleted
     */
    event StrategyDeleted(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        GradientOrder order
    );

    /**
     * @dev triggered when a gradient strategy is updated
     */
    event StrategyUpdated(
        uint256 indexed id,
        Token indexed token0,
        Token indexed token1,
        GradientOrder order,
        uint8 reason
    );

    /**
     * @dev triggered when tokens are traded
     */
    event GradientStrategyTokensTraded(
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
        GradientOrder memory order,
        Pair memory pair,
        address owner,
        uint256 value
    ) internal returns (uint256) {
        // transfer funds
        _validateDepositAndRefundExcessNativeToken(tokens[0], owner, order.sourceAmount, value, true);
        _validateDepositAndRefundExcessNativeToken(tokens[1], owner, order.targetAmount, value, true);

        // store id
        uint128 counter = _strategyCounter + 1;
        _strategyCounter = counter;
        uint256 id = _strategyId(pair.id, counter);
        _strategyIdsByPairIdStorage[pair.id].add(id);

        // store order
        order.tokensInverted = tokens[0] == pair.tokens[1];
        _gradientOrderByStrategyId[id] = order;

        // mint voucher
        voucher.mint(owner, id);

        // emit event
        emit StrategyCreated({ id: id, owner: owner, token0: tokens[0], token1: tokens[1], order: order });

        return id;
    }

    /**
     * @dev updates an existing strategy
     */
    function _updateStrategy(
        uint256 strategyId,
        GradientOrder calldata currentOrder,
        GradientOrder calldata newOrder,
        Pair memory pair,
        address owner,
        uint256 value
    ) internal {
        GradientOrder storage order = _gradientOrderByStrategyId[strategyId];
        GradientOrder memory orderMemory = order;

        // revert if the strategy mutated since this tx was sent
        if (!_equalStrategyOrders(currentOrder, order)) {
            revert OutDated();
        }

        // store new values if necessary
        if (orderMemory.targetAmount != newOrder.targetAmount) {
            order.targetAmount = newOrder.targetAmount;
        }
        if (notEqual(orderMemory.curve, newOrder.curve)) {
            order.curve = newOrder.curve;
        }
        if (
            orderMemory.initialPrice.sourceAmount != newOrder.initialPrice.sourceAmount ||
            orderMemory.initialPrice.targetAmount != newOrder.initialPrice.targetAmount
        ) {
            order.initialPrice = newOrder.initialPrice;
        }
        if (
            orderMemory.endPrice.sourceAmount != newOrder.endPrice.sourceAmount ||
            orderMemory.endPrice.targetAmount != newOrder.endPrice.targetAmount
        ) {
            order.endPrice = newOrder.endPrice;
        }
        // update expiry of order
        if (newOrder.expiry == 0) {
            order.expiry = uint32(block.timestamp + DEFAULT_EXPIRY);
        } else if (orderMemory.expiry != newOrder.expiry) {
            order.expiry = newOrder.expiry;
        }
        // update tradingStartTime of order
        if (order.tradingStartTime == 0) {
            order.tradingStartTime = orderMemory.tradingStartTime;
        } else if (order.tradingStartTime < uint32(block.timestamp)) {
            order.tradingStartTime = uint32(block.timestamp);
        } else {
            order.tradingStartTime = newOrder.tradingStartTime;
        }

        // deposit and withdraw
        Token[2] memory sortedTokens = _sortStrategyTokens(pair, orderMemory.tokensInverted);
        Token token = sortedTokens[1];
        if (newOrder.targetAmount < orderMemory.targetAmount) {
            // liquidity decreased - withdraw the difference
            uint128 delta = orderMemory.targetAmount - newOrder.targetAmount;
            _withdrawFunds(token, payable(owner), delta);
        } else if (newOrder.targetAmount > orderMemory.targetAmount) {
            // liquidity increased - deposit the difference
            uint128 delta = newOrder.targetAmount - orderMemory.targetAmount;
            _validateDepositAndRefundExcessNativeToken(token, owner, delta, value, true);
        }

        // refund native token when there's no deposit in the order
        // note that deposit handles refunds internally
        if (value > 0 && token.isNative() && newOrder.targetAmount <= orderMemory.targetAmount) {
            payable(address(owner)).sendValue(value);
        }

        // emit event
        emit StrategyUpdated({
            id: strategyId,
            token0: sortedTokens[0],
            token1: sortedTokens[1],
            order: newOrder,
            reason: STRATEGY_UPDATE_REASON_EDIT
        });
    }

    /**
     * @dev deletes a strategy
     */
    function _deleteStrategy(uint256 strategyId, IVoucher voucher, Pair memory pair) internal {
        GradientStrategy memory strategy = _strategy(strategyId, voucher, pair);

        // burn the voucher nft token
        voucher.burn(strategy.id);

        // clear storage
        delete _gradientOrderByStrategyId[strategy.id];
        _strategyIdsByPairIdStorage[pair.id].remove(strategy.id);

        // withdraw funds
        _withdrawFunds(strategy.tokens[0], payable(strategy.owner), strategy.order.sourceAmount);
        _withdrawFunds(strategy.tokens[1], payable(strategy.owner), strategy.order.targetAmount);

        // emit event
        emit StrategyDeleted({
            id: strategy.id,
            owner: strategy.owner,
            token0: strategy.tokens[0],
            token1: strategy.tokens[1],
            order: strategy.order
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
        // process trade actions
        for (uint256 i = 0; i < tradeActions.length; i = uncheckedInc(i)) {
            // prepare variables
            uint128 amount = tradeActions[i].amount;
            uint256 strategyId = tradeActions[i].strategyId;
            GradientOrder storage order = _gradientOrderByStrategyId[strategyId];
            GradientOrder memory orderMemory = order;
            Token[2] memory sortedTokens = _sortStrategyTokens(params.pair, orderMemory.tokensInverted);

            _validateTradeParams(params.pair.id, strategyId, sortedTokens[0], params.tokens.source, amount);

            // validate order can be traded
            _validateTradeOrder(orderMemory);

            // calculate the orders new values
            (uint128 sourceAmount, uint128 targetAmount) = _singleTradeActionSourceAndTargetAmounts(
                orderMemory,
                amount,
                params.byTargetAmount
            );

            // handled specifically for a custom error message
            if (order.targetAmount < targetAmount) {
                revert InsufficientLiquidity();
            }

            // update the orders with the new values
            // safe since it's checked above
            unchecked {
                order.targetAmount -= targetAmount;
            }

            order.sourceAmount += sourceAmount;

            // emit event
            emit StrategyUpdated({
                id: strategyId,
                token0: sortedTokens[0],
                token1: sortedTokens[1],
                order: order,
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
        emit GradientStrategyTokensTraded({
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
        // process trade actions
        for (uint256 i = 0; i < tradeActions.length; i = uncheckedInc(i)) {
            // prepare variables
            uint128 amount = tradeActions[i].amount;
            uint256 strategyId = tradeActions[i].strategyId;
            GradientOrder storage order = _gradientOrderByStrategyId[strategyId];
            GradientOrder memory orderMemory = order;
            Token[2] memory sortedTokens = _sortStrategyTokens(pair, orderMemory.tokensInverted);

            _validateTradeParams(pair.id, strategyId, sortedTokens[0], tokens.source, amount);

            // calculate the orders new values
            (uint128 sourceAmount, uint128 targetAmount) = _singleTradeActionSourceAndTargetAmounts(
                orderMemory,
                amount,
                byTargetAmount
            );

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
    ) internal view returns (GradientStrategy[] memory) {
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
        GradientStrategy[] memory result = new GradientStrategy[](resultLength);
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
     @dev returns a gradient strategy object matching the provided id.
     */
    function _strategy(uint256 id, IVoucher voucher, Pair memory pair) internal view returns (GradientStrategy memory) {
        // fetch data
        address _owner = voucher.ownerOf(id);
        GradientOrder memory order = _gradientOrderByStrategyId[id];

        // handle sorting
        Token[2] memory sortedTokens = _sortStrategyTokens(pair, order.tokensInverted);

        return GradientStrategy({ id: id, owner: _owner, tokens: sortedTokens, order: order });
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

    function _validateTradeParams(
        uint256 pairId,
        uint256 strategyId,
        Token orderSourceToken,
        Token tradeSourceToken,
        uint128 tradeAmount
    ) private pure {
        // make sure the strategy id matches the pair id
        if (_pairIdByStrategyId(strategyId) != pairId) {
            revert InvalidTradeActionStrategyId();
        }

        // make sure trade source token matches the order source token
        if (orderSourceToken != tradeSourceToken) {
            revert InvalidTradeActionSourceToken();
        }

        // make sure the trade amount is nonzero
        if (tradeAmount == 0) {
            revert InvalidTradeActionAmount();
        }
    }

    function _validateTradeOrder(GradientOrder memory order) private view {
        if (order.tradingStartTime > block.timestamp) {
            revert OrderDisabled();
        }
        if (order.expiry <= block.timestamp) {
            revert OrderExpired();
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
    function _equalStrategyOrders(
        GradientOrder memory order0,
        GradientOrder memory order1
    ) internal pure returns (bool) {
        if (
            order0.initialPrice.sourceAmount != order1.initialPrice.sourceAmount ||
            order0.initialPrice.targetAmount != order1.initialPrice.targetAmount ||
            order0.endPrice.sourceAmount != order1.endPrice.sourceAmount ||
            order0.endPrice.targetAmount != order1.endPrice.targetAmount ||
            order0.sourceAmount != order1.sourceAmount ||
            order0.targetAmount != order1.targetAmount ||
            order0.tradingStartTime != order1.tradingStartTime ||
            order0.expiry != order1.expiry ||
            order0.tokensInverted != order1.tokensInverted ||
            notEqual(order0.curve, order1.curve)
        ) {
            return false;
        }
        return true;
    }

    /**
     * @dev returns the source and target amounts of a single trade action
     */
    function _singleTradeActionSourceAndTargetAmounts(
        GradientOrder memory order,
        uint128 amount,
        bool byTargetAmount
    ) internal view returns (uint128 sourceAmount, uint128 targetAmount) {
        if (byTargetAmount) {
            sourceAmount = expectedTradeInput(order, amount);
            targetAmount = amount;
        } else {
            sourceAmount = amount;
            targetAmount = expectedTradeReturn(order, amount);
        }
    }

    /**
     * @notice returns the current token price for a given a gradient order
     */
    function tokenPrice(GradientOrder memory order) public view returns (Price memory) {
        // get time elapsed since trading was enabled
        uint32 timeElapsed = uint32(block.timestamp) - order.tradingStartTime;
        // cache prices to save gas
        Price memory price = order.initialPrice;
        Price memory endPrice = order.endPrice;
        // get the current price by adjusting the amount with the decay formula
        if (order.curve.curveType == GradientCurveTypes.LINEAR) {
            price.sourceAmount = DecayMath
                .calcLinearDecay(
                    price.sourceAmount,
                    timeElapsed,
                    order.curve.increaseAmount,
                    order.curve.increaseInterval,
                    order.curve.isDutchAuction
                )
                .toUint128();
        } else if (order.curve.curveType == GradientCurveTypes.EXPONENTIAL) {
            if (order.curve.isDutchAuction) {
                price.sourceAmount = DecayMath
                    .calcExpDecay(price.sourceAmount, timeElapsed, order.curve.halflife)
                    .toUint128();
            } else {
                price.targetAmount = DecayMath
                    .calcExpDecay(price.targetAmount, timeElapsed, order.curve.halflife)
                    .toUint128();
            }
        }
        // if price is lower than the end price, set it to the end price
        // @TODO: optimize this
        if (order.curve.isDutchAuction) {
            // sourceAmount is decreasing in both cases if dutch auction
            price.sourceAmount = Math.min(price.sourceAmount, endPrice.sourceAmount).toUint128();
        } else {
            // source amount is increasing in linear case if regular auction
            if (order.curve.curveType == GradientCurveTypes.LINEAR) {
                price.sourceAmount = Math.max(price.sourceAmount, endPrice.sourceAmount).toUint128();
                // target amount is decreasing in exponential case if regular auction
            } else if (order.curve.curveType == GradientCurveTypes.EXPONENTIAL) {
                price.targetAmount = Math.min(price.targetAmount, endPrice.targetAmount).toUint128();
            }
        }
        // return the price
        return price;
    }

    /**
     * @notice returns the target amount expected given a source amount
     */
    function expectedTradeReturn(GradientOrder memory order, uint128 sourceAmount) public view returns (uint128) {
        Price memory currentPrice = tokenPrice(order);
        // revert if price is not valid
        _validPrice(currentPrice);
        // calculate the target amount based on the current price and token
        uint128 targetAmount = MathEx
            .mulDivF(currentPrice.targetAmount, sourceAmount, currentPrice.sourceAmount)
            .toUint128();
        return targetAmount;
    }

    /**
     * @notice returns the source amount required given a target amount
     */
    function expectedTradeInput(GradientOrder memory order, uint128 targetAmount) public view returns (uint128) {
        Price memory currentPrice = tokenPrice(order);
        // revert if current price is not valid
        _validPrice(currentPrice);
        // calculate the trade input based on the current price
        return MathEx.mulDivF(currentPrice.sourceAmount, targetAmount, currentPrice.targetAmount).toUint128();
    }

    /**
     * @dev validate token helper
     */
    function _validPrice(Price memory price) private pure {
        if (price.sourceAmount == 0 || price.targetAmount == 0) {
            revert InvalidPrice();
        }
    }

    /**
     * revert if an order is invalid
     */
    function _validateOrder(GradientOrder calldata order) internal view {
        if (
            order.curve.curveType == GradientCurveTypes.LINEAR &&
            (order.curve.increaseAmount == 0 || order.curve.increaseInterval == 0)
        ) {
            revert InvalidOrderCurve();
        }
        if (order.curve.curveType == GradientCurveTypes.EXPONENTIAL && (order.curve.halflife == 0)) {
            revert InvalidOrderCurve();
        }
        if (order.expiry != 0 && order.expiry <= uint32(block.timestamp)) {
            revert InvalidExpiry();
        }
        if (order.initialPrice.sourceAmount == 0 || order.initialPrice.targetAmount == 0) {
            revert InvalidOrderInitialPrice();
        }
        if (
            order.endPrice.sourceAmount > order.initialPrice.sourceAmount ||
            order.endPrice.targetAmount > order.initialPrice.targetAmount
        ) {
            revert InvalidOrderEndPrice();
        }
        if (order.targetAmount == 0) {
            revert InvalidOrderTargetAmount();
        }
    }

    /**
     * returns the strategyId for a given pairId and a given strategyIndex
     * MSB is set to 1 to indicate gradient strategies
     */
    function _strategyId(uint128 pairId, uint128 strategyIndex) internal pure returns (uint256) {
        return (uint256(pairId) << 128) | strategyIndex | MSB_MASK;
    }

    /**
     * returns the pairId associated with a given strategyId
     */
    function _pairIdByStrategyId(uint256 strategyId) internal pure returns (uint128) {
        return uint128((strategyId & ~MSB_MASK) >> 128);
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
     * returns tokens sorted accordingly to a strategy order tokens inversion
     */
    function _sortStrategyTokens(Pair memory pair, bool tokensInverted) private pure returns (Token[2] memory) {
        return tokensInverted ? [pair.tokens[1], pair.tokens[0]] : pair.tokens;
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
