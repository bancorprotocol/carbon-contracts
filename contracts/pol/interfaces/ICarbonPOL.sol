// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @dev CarbonPOL interface
 */
interface ICarbonPOL is IUpgradeable {
    error DuplicateToken();
    error InvalidToken();
    error InvalidTokenLength();
    error TokenPoolFeesLengthMismatch();

    /**
     * @dev triggered after a successful trade is executed
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
     * @dev triggered when the rewards ppm are updated
     */
    event RewardsUpdated(
        uint32 prevRewardsPPM,
        uint32 newRewardsPPM
    );

    /**
     * @dev triggered when the max slippage ppm is updated
     */
    event MaxSlippageUpdated(
        uint32 prevMaxSlippagePPM,
        uint32 newMaxSlippagePPM
    );

    /**
     * @dev triggered when the max tradeable ppm per block is updated
     */
    event MaxTradeableUpdated(
        uint32 prevMaxTradeablePPB,
        uint32 newMaxTradeablePPB
    );

    /**
     * @dev returns the rewards ppm
     */
    function rewardsPPM() external view returns (uint32);

    /**
     * @dev returns the max slippage ppm
     */
    function maxSlippagePPM() external view returns (uint32);

    /**
     * @dev returns the max tradeable ppb per block
     */
    function maxTradeablePPB() external view returns (uint32);

    /**
     * @dev returns the last block a token was traded in
     */
    function lastTradedBlock(Token token) external view returns (uint256);

    /**
     * @dev returns the current max tradeable amount for a token
     */
    function maxTradeableAmount(Token token) external view returns (uint256);
    
    /**
     * @dev converts the given tokens using Uni V3 to ETH in the pools with selected fees
     * @dev rewards the user with *rewardsPPM* of each token
     */
    function tradeTokens(Token[] calldata tokens, uint24[] calldata poolFees) external;

    /**
     * @dev sets the rewards ppm
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setRewardsPPM(uint32 newRewardsPPM) external;

    /**
     * @dev sets the max slippage ppm
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMaxSlippagePPM(uint32 newMaxSlippagePPM) external;

    /**
     * @dev sets the max tradeable ppb
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMaxTradeablePPB(uint32 newMaxTradeablePPB) external;
}
