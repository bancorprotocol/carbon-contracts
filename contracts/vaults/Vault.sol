// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IVault, ROLE_ASSET_MANAGER } from "./interfaces/IVault.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token } from "../token/Token.sol";
import { TokenLibrary } from "../token/TokenLibrary.sol";
import { Utils, AccessDenied, NotPayable, InvalidToken } from "../utility/Utils.sol";
import { MAX_GAP } from "../utility/Constants.sol";

abstract contract Vault is IVault, Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, Utils {
    using Address for address payable;
    using SafeERC20 for IERC20;
    using TokenLibrary for Token;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 0] private __gap;

    // solhint-disable func-name-mixedcase

    /**
     * @dev a "virtual" constructor that is only used to set immutable state variables
     */
    constructor() {}

    /**
     * @dev initializes the contract and its parents
     */
    function __Vault_init() internal onlyInitializing {
        __Upgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        __Vault_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __Vault_init_unchained() internal onlyInitializing {}

    // solhint-enable func-name-mixedcase

    /**
     * @dev returns the asset manager role
     */
    function roleAssetManager() external pure returns (bytes32) {
        return ROLE_ASSET_MANAGER;
    }

    // allows execution only by an authorized operation
    modifier whenAuthorized(
        address caller,
        Token token,
        address payable target,
        uint256 amount
    ) {
        if (!isAuthorizedWithdrawal(caller, token, target, amount)) {
            revert AccessDenied();
        }

        _;
    }

    /**
     * @dev returns whether withdrawals are currently paused
     */
    function isPaused() external view returns (bool) {
        return paused();
    }

    /**
     * @dev pauses withdrawals
     *
     * requirements:
     *
     * - the caller must have the ROLE_ADMIN privileges
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @dev unpauses withdrawals
     *
     * requirements:
     *
     * - the caller must have the ROLE_ADMIN privileges
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    /**
     * @inheritdoc IVault
     */
    function withdrawFunds(
        Token token,
        address payable target,
        uint256 amount
    ) external validAddress(target) nonReentrant whenNotPaused whenAuthorized(msg.sender, token, target, amount) {
        if (amount == 0) {
            return;
        }

        if (token.isNative()) {
            // using a regular transfer here would revert due to exceeding the 2300 gas limit which is why we're using
            // call instead (via sendValue), which the 2300 gas limit does not apply for
            target.sendValue(amount);
        } else {
            token.safeTransfer(target, amount);
        }

        emit FundsWithdrawn({ token: token, caller: msg.sender, target: target, amount: amount });
    }

    /**
     * @dev returns whether the given caller is allowed access to the given token
     */
    function isAuthorizedWithdrawal(
        address caller,
        Token token,
        address target,
        uint256 amount
    ) internal view virtual returns (bool);

    /**
     * @inheritdoc IVault
     */
    function isPayable() public view virtual returns (bool);

    /**
     * @dev authorize the contract to receive the native token
     *
     * requirements:
     *
     * - isPayable must return true
     */
    receive() external payable {
        if (!isPayable()) {
            revert NotPayable();
        }
    }
}
