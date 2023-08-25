// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @notice CarbonPOL interface
 */
interface ICarbonPOL is IUpgradeable {
    error DuplicateToken();
    error InvalidToken();
    error InvalidTokenLength();
    error TokenPoolFeesLengthMismatch();

    /**
     * @notice triggered after a successful trade is executed
     */
    event TokensTraded(
        address indexed caller,
        Token[] tokens,
        uint24[] poolFees,
        uint256[] tradeAmounts,
        uint256[] rewardAmounts,
        uint256 ethReceived
    );

    /**
     * @notice triggered when the rewards ppm are updated
     */
    event RewardsUpdated(
        uint32 prevRewardsPPM,
        uint32 newRewardsPPM
    );

    /**
     * @notice triggered when the max slippage ppm is updated
     */
    event MaxSlippageUpdated(
        uint32 prevMaxSlippagePPM,
        uint32 newMaxSlippagePPM
    );

    /**
     * @notice triggered when the max tradeable ppm per block is updated
     */
    event MaxTradeableUpdated(
        uint32 prevMaxTradeablePPB,
        uint32 newMaxTradeablePPB
    );

    /**
     * @notice returns the rewards ppm
     */
    function rewardsPPM() external view returns (uint32);

    /**
     * @notice returns the max slippage ppm
     */
    function maxSlippagePPM() external view returns (uint32);

    /**
     * @notice returns the max tradeable ppb per block
     */
    function maxTradeablePPB() external view returns (uint32);

    /**
     * @notice returns the last block a token was traded in
     */
    function lastTradedBlock(Token token) external view returns (uint256);

    /**
     * @notice returns the current max tradeable amount for a token
     */
    function maxTradeableAmount(Token token) external view returns (uint256);
    
    /**
     * @notice converts the given tokens using Uni V3 to ETH in the pools with selected fees
     * @notice rewards the user with *rewardsPPM* of each token
     */
    function tradeTokens(Token[] calldata tokens, uint24[] calldata poolFees) external;
}
