// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import { IERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";

/**
 * @dev Voucher interface
 */
interface IVoucher is IUpgradeable, IERC721Upgradeable {
    error ControllerAlreadySet();
    error OnlyController();

    /**
     * @dev returns the controller address
     */
    function controller() external view returns (address);
    
    /**
     * @dev creates a new voucher token for the given strategyId, transfers it to the owner
     *
     * requirements:
     *
     * - the caller must be the controller address
     *
     */
    function mint(address owner, uint256 strategyId) external;

    /**
     * @dev destroys the voucher token for the given strategyId
     *
     * requirements:
     *
     * - the caller must be the controller address
     *
     */
    function burn(uint256 strategyId) external;

    /**
     * @dev returns a list of tokenIds belonging to the given owner
     * note that for the full list of tokenIds pass 0 to both startIndex and endIndex
     */
    function tokensByOwner(
        address owner,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (uint256[] memory);
}
