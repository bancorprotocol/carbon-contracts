// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";

import { Token } from "../token/Token.sol";
import { TokenLibrary } from "../token/TokenLibrary.sol";

import { IMasterVault } from "./interfaces/IMasterVault.sol";
import { IVault, ROLE_ASSET_MANAGER } from "./interfaces/IVault.sol";
import { Vault } from "./Vault.sol";
import { MAX_GAP } from "../utility/Constants.sol";

/**
 * @dev Master Vault contract
 */
contract MasterVault is IMasterVault, Vault {
    using SafeERC20 for IERC20;
    using TokenLibrary for Token;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 0] private __gap;

    /**
     * @dev a "virtual" constructor that is only used to set immutable state variables
     */
    constructor() Vault() {}

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() external initializer {
        __MasterVault_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __MasterVault_init() internal onlyInitializing {
        __Vault_init();

        __MasterVault_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __MasterVault_init_unchained() internal onlyInitializing {
        // set up administrative roles
        _setRoleAdmin(ROLE_ASSET_MANAGER, ROLE_ADMIN);
    }

    // solhint-enable func-name-mixedcase

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 1;
    }

    /**
     * @inheritdoc Vault
     */
    function isPayable() public pure override(IVault, Vault) returns (bool) {
        return true;
    }

    /**
     * @dev authorize the right of a caller to withdraw a specific amount of a token to a target
     *
     * requirements:
     *
     * - the caller must have the ROLE_ASSET_MANAGER role
     */
    function isAuthorizedWithdrawal(
        address caller,
        Token, /* token */
        address, /* target */
        uint256 /* amount */
    ) internal view override returns (bool) {
        return hasRole(ROLE_ASSET_MANAGER, caller);
    }
}
