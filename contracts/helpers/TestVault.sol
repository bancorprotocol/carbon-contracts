// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import { Token } from "../token/Token.sol";

import { Utils, AccessDenied } from "../utility/Utils.sol";

contract TestVault is ReentrancyGuard, AccessControlEnumerable, Utils {
    using Address for address payable;
    using SafeERC20 for IERC20;

    // the admin role is used to grant and revoke the asset manager role
    bytes32 internal constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    // the asset manager role is required to access all the funds
    bytes32 private constant ROLE_ASSET_MANAGER = keccak256("ROLE_ASSET_MANAGER");

    /**
     * @dev triggered when tokens have been withdrawn from the vault
     */
    event FundsWithdrawn(Token indexed token, address indexed caller, address indexed target, uint256 amount);

    /**
     * @dev used to initialize the implementation
     */
    constructor() {
        // set up administrative roles
        _setRoleAdmin(ROLE_ADMIN, ROLE_ADMIN);
        _setRoleAdmin(ROLE_ASSET_MANAGER, ROLE_ADMIN);
        // allow the deployer to initially be the admin of the contract
        _setupRole(ROLE_ADMIN, msg.sender);
    }

    // solhint-enable func-name-mixedcase

    /**
     * @dev authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @dev returns the admin role
     */
    function roleAdmin() external pure returns (bytes32) {
        return ROLE_ADMIN;
    }

    /**
     * @dev returns the asset manager role
     */
    function roleAssetManager() external pure returns (bytes32) {
        return ROLE_ASSET_MANAGER;
    }

    /**
     * @dev withdraws funds held by the contract and sends them to an account
     */
    function withdrawFunds(
        Token token,
        address payable target,
        uint256 amount
    ) external validAddress(target) nonReentrant {
        if (!hasRole(ROLE_ASSET_MANAGER, msg.sender)) {
            revert AccessDenied();
        }

        if (amount == 0) {
            return;
        }

        // safe due to nonReentrant modifier (forwards all available gas in case of ETH)
        token.unsafeTransfer(target, amount);

        emit FundsWithdrawn({ token: token, caller: msg.sender, target: target, amount: amount });
    }
}
