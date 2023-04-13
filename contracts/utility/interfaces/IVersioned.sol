// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @dev an interface for a versioned contract
 */
interface IVersioned {
    function version() external view returns (uint16);
}
