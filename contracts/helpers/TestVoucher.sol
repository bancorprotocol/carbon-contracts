// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Voucher } from "../voucher/Voucher.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TestVoucher is Voucher {
    using EnumerableSet for EnumerableSet.UintSet;

    constructor(
        bool newUseGlobalURI,
        string memory newBaseURI,
        string memory newBaseExtension
    ) Voucher(newUseGlobalURI, newBaseURI, newBaseExtension) {}

    function testMintAndMapToOwner(address owner, uint256 tokenId) external {
        _mintAndMapToOwner(owner, tokenId);
    }
}
