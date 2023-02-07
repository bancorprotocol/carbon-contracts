// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import { IVersioned } from "../../utility/interfaces/IVersioned.sol";
import { Pool } from "../Pools.sol";
import { Token } from "../../token/Token.sol";
import { IMasterVault } from "../../vaults/interfaces/IMasterVault.sol";
import { Strategy, TradeAction, Order } from "../Strategies.sol";

/**
 * @dev Carbon Controller interface
 */
interface ICarbonController is IVersioned {
    /**
     * @dev returns the type of the pool
     */
    function controllerType() external view returns (uint16);

    /**
     * @dev returns the trading fee (in units of PPM)
     */
    function tradingFeePPM() external view returns (uint32);

    /**
     * @dev creates a new pool of provided token0 and token1
     */
    function createPool(Token token0, Token token1) external returns (Pool memory);

    /**
     * @dev returns a pool's metadata matching the provided token0 and token1
     */
    function pool(Token token0, Token token1) external view returns (Pool memory);

    /**
     * @dev returns a list of all supported pairs
     */
    function pairs() external view returns (address[2][] memory);

    // solhint-disable var-name-mixedcase
    /**
     * @dev creates a new strategy, returns the strategy's id
     *
     * requirements:
     *
     * - the caller must have approved the tokens with assigned liquidity in the order, if any
     */
    function createStrategy(
        Token token0,
        Token token1,
        Order[2] calldata orders
    ) external payable returns (uint256);

    /**
     * @dev updates an existing strategy
     *
     * notes:
     * - currentOrders should reflect the orders values at the time of sending the tx
     * - reduced liquidity is refunded to the owner
     * - increased liquidity is deposited to the vault
     * - excess native token is returned to the sender if any
     *
     * requirements:
     *
     * - the caller must have approved the tokens with increased liquidity, if any
     */
    function updateStrategy(
        uint256 strategyId,
        Order[2] memory currentOrders,
        Order[2] memory newOrders
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
     * @dev returns a strategy matching the provided id
     */
    function strategy(uint256 id) external view returns (Strategy memory);

    /**
     * @dev returns strategies matching provided ids
     */
    function strategiesByIds(uint256[] calldata ids) external view returns (Strategy[] memory);

    /**
     * @dev returns strategies belonging to a specific pool
     * note for the full list of strategies pass 0 to both startIndex and endIndex
     */
    function strategiesByPool(
        Token token0,
        Token token1,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (Strategy[] memory);

    /**
     * @dev returns the count of strategies belonging to a specific pool
     */
    function strategiesByPoolCount(Token token0, Token token1) external view returns (uint256);

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
        uint112 minReturn
    ) external payable returns (uint112);

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
        uint112 maxInput
    ) external payable returns (uint112);

    /**
     * @dev returns the source amount required when trading by target amount
     */
    function tradeSourceAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint112);

    /**
     * @dev returns the target amount expected when trading by source amount
     */
    function tradeTargetAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint112);

    /**
     * @dev returns the amount of fees accumulated for the specified token
     */
    function accumulatedFees(address token) external view returns (uint256);
}
