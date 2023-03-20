// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @dev Voucher interface
 */
interface IVoucher is IERC721Enumerable {
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
    function burn(uint256 strategyId) external;
}
