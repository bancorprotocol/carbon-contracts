// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @dev Voucher interface
 */
interface IVoucher is IERC721 {
    /**
     * @dev creatds a new voucher token for the given strategyId, transfers it to the provider
     *
     * requirements:
     *
     * - the caller must be the carbonController contract
     *
     */
    function mint(address provider, uint256 strategyId) external;

    /**
     * @dev destorys the voucher token for the given strategyId
     *
     * requirements:
     *
     * - the caller must be the carbonController contract
     *
     */
    function burn(address provider, uint256 strategyId) external;
}
