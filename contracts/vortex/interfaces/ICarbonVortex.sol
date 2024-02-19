// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @dev CarbonVortex interface
 */
interface ICarbonVortex is IUpgradeable {
    error DuplicateToken();
    error InvalidToken();
    error InvalidTokenLength();

    /**
     * @dev triggered after a successful burn is executed
     */
    event TokensBurned(address indexed caller, Token[] tokens, uint256[] rewardAmounts, uint256 burnAmount);

    /**
     * @dev triggered when the rewards ppm are updated
     */
    event RewardsUpdated(uint256 prevRewardsPPM, uint256 newRewardsPPM);

    /**
     * @dev triggered when tokens have been withdrawn by the admin
     */
    event FundsWithdrawn(Token indexed token, address indexed caller, address indexed target, uint256 amount);

    /**
     * @dev returns the rewards percentage ppm
     */
    function rewardsPPM() external view returns (uint256);

    /**
     * @dev returns the total amount burned
     */
    function totalBurned() external view returns (uint256);

    /**
     * @dev returns the total available fees for the given token
     */
    function availableTokens(Token token) external view returns (uint256);

    /**
     * @dev withdraws the fees of the provided tokens from Carbon
     * @dev converts them along with the available contract token balance to BNT,
     * @dev rewards the caller and burns the rest of the tokens
     */
    function execute(Token[] calldata tokens) external;

    /**
     * @dev sets the rewards percentage ppm
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setRewardsPPM(uint256 newRewardsPercentagePPM) external;
}
