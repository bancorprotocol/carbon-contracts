// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IVersioned } from "./IVersioned.sol";

import { IAccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/IAccessControlEnumerableUpgradeable.sol";

/**
 * @dev this is the common interface for upgradeable contracts
 */
interface IUpgradeable is IAccessControlEnumerableUpgradeable, IVersioned {

}
