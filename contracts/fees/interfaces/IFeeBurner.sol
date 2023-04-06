// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @dev FeeBurner interface
 */
interface IFeeBurner is IUpgradeable {
    // rewards settings
    struct Rewards {
        uint32 percentagePPM;
        uint224 maxAmount;
    }

    error InvalidToken();

    /**
     * @dev triggered after a successful burn is executed
     */
    event FeesBurnt(
        address indexed caller,
        uint256 burnAmount,
        uint256 rewardAmount
    );

    /**
     * @dev triggered when the rewards settings are updated
     */
    event RewardsUpdated(
        uint32 prevPercentagePPM,
        uint32 newPercentagePPM,
        uint224 prevMaxAmount,
        uint224 newMaxAmount
    );

    /**
     * @dev returns the rewards settings
     */
    function rewards() external view returns (Rewards memory);
    
    /**
     * @dev withdraws the fees of the provided tokens from Carbon
     * @dev converts them to BNT, 
     * @dev rewards the caller and burns the rest of the tokens
     */
    function burn(Token[] calldata tokens) external;

    /**
     * @dev sets the rewards settings
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setRewards(Rewards memory newRewards) external;
}
