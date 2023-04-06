// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @dev this contract abstracts the block number in order to allow for more flexible control in tests
 */
abstract contract BlockNumber {
    /**
     * @dev returns the current block-number
     */
    function _blockNumber() internal view virtual returns (uint32) {
        return uint32(block.number);
    }
}
