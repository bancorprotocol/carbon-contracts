// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Pair } from "../Pairs.sol";
import { Token } from "../../token/Token.sol";
import { Strategy, TradeAction, Order } from "../Strategies.sol";

/**
 * @dev Carbon Controller interface
 */
interface ICarbonController is IUpgradeable {
    /**
     * @dev returns the type of the controller
     */
    function controllerType() external pure returns (uint16);

    /**
     * @dev returns the trading fee (in units of PPM)
     */
    function tradingFeePPM() external view returns (uint32);

    /**
     * @dev returns the trading fee for a given pair (in units of PPM)
     */
    function pairTradingFeePPM(Token token0, Token token1) external view returns (uint32);

    /**
     * @dev creates a new pair of provided token0 and token1
     */
    function createPair(Token token0, Token token1) external returns (Pair memory);

    /**
     * @dev returns a pair's metadata matching the provided token0 and token1
     */
    function pair(Token token0, Token token1) external view returns (Pair memory);

    /**
     * @dev returns a list of all supported pairs
     */
    function pairs() external view returns (Token[2][] memory);

    // solhint-disable var-name-mixedcase
    /**
     * @dev creates a new strategy, returns the strategy's id
     *
     * requirements:
     *
     * - the caller must have approved the tokens with assigned liquidity in the order, if any
     */
    function createStrategy(Token token0, Token token1, Order[2] calldata orders) external payable returns (uint256);

    /**
     * @dev updates an existing strategy
     *
     * notes:
     * - currentOrders should reflect the orders values at the time of sending the tx
     * this prevents cases in which the strategy was updated due to a trade between
     * the time the transaction was sent and the time it was mined, thus, giving more
     * control to the strategy owner.
     * - reduced liquidity is refunded to the owner
     * - increased liquidity is deposited
     * - excess native token is returned to the sender if any
     * - the sorting of orders is expected to equal the sorting upon creation
     *
     * requirements:
     *
     * - the caller must have approved the tokens with increased liquidity, if any
     */
    function updateStrategy(
        uint256 strategyId,
        Order[2] calldata currentOrders,
        Order[2] calldata newOrders
    ) external payable;

    // solhint-enable var-name-mixedcase

    /**
     * @dev deletes a strategy matching the provided id
     *
     * notes:
     *
     * - 100% of liquidity is withdrawn and sent to the owner
     *
     * requirements:
     *
     * - the caller must be the owner of the NFT voucher
     */
    function deleteStrategy(uint256 strategyId) external;

    /**
     * @dev returns a strategy matching the provided id,
     * note tokens and orders are returned sorted as provided upon creation
     */
    function strategy(uint256 id) external view returns (Strategy memory);

    /**
     * @dev returns strategies belonging to a specific pair
     * note that for the full list of strategies pass 0 to both startIndex and endIndex
     */
    function strategiesByPair(
        Token token0,
        Token token1,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (Strategy[] memory);

    /**
     * @dev returns the count of strategies belonging to a specific pair
     */
    function strategiesByPairCount(Token token0, Token token1) external view returns (uint256);

    /**
     * @dev performs a trade by specifying a fixed source amount
     *
     * notes:
     *
     * - excess native token is returned to the sender if any
     *
     * requirements:
     *
     * - the caller must have approved the source token
     */
    function tradeBySourceAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions,
        uint256 deadline,
        uint128 minReturn
    ) external payable returns (uint128);

    /**
     * @dev performs a trade by specifying a fixed target amount
     *
     * notes:
     *
     * - excess native token is returned to the sender if any
     *
     * requirements:
     *
     * - the caller must have approved the source token
     */
    function tradeByTargetAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions,
        uint256 deadline,
        uint128 maxInput
    ) external payable returns (uint128);

    /**
     * @dev returns the source amount required when trading by target amount
     */
    function calculateTradeSourceAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint128);

    /**
     * @dev returns the target amount expected when trading by source amount
     */
    function calculateTradeTargetAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint128);

    /**
     * @dev returns the amount of fees accumulated for the specified token
     */
    function accumulatedFees(Token token) external view returns (uint256);

    /**
     * @dev transfers the accumulated fees to the specified recipient
     *
     * notes:
     * `amount` is capped to the available amount
     * returns the amount withdrawn
     */
    function withdrawFees(Token token, uint256 amount, address recipient) external returns (uint256);
}
