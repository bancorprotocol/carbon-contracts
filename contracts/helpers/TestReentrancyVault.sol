// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Vault } from "../vault/Vault.sol";
import { Token } from "../token/Token.sol";

/**
 * @dev test re-entrancy protection for Vault
 */
contract TestReentrancyVault {
    Vault private immutable _vault;
    Token private immutable _token;

    constructor(Vault vaultInit, Token tokenInit) {
        _vault = vaultInit;
        _token = tokenInit;
    }

    receive() external payable {
        // re-enter withdrawFunds, reverting the tx
        _vault.withdrawFunds(_token, payable(address(this)), 1000);
    }

    /// @dev try to reenter withdraw funds
    function tryReenterWithdrawFunds(Token token, address payable target, uint256 amount) external {
        _vault.withdrawFunds(token, target, amount);
    }
}
