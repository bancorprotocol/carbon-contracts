// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev This type implements ERC20 and SafeERC20 utilities for both the native token and for ERC20 tokens
 */
type Token is address;
using SafeERC20 for IERC20;

// the address that represents the native token reserve
address constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

// the symbol that represents the native token
string constant NATIVE_TOKEN_SYMBOL = "ETH";

// the decimals for the native token
uint8 constant NATIVE_TOKEN_DECIMALS = 18;

// the token representing the native token
Token constant NATIVE_TOKEN = Token.wrap(NATIVE_TOKEN_ADDRESS);

using {
    equal as ==,
    isNative,
    symbol,
    decimals,
    balanceOf,
    safeTransfer,
    safeTransferFrom,
    safeApprove
} for Token global;

function equal(Token a, Token b) pure returns (bool) {
    return Token.unwrap(a) == Token.unwrap(b);
}

/**
 * @dev returns whether the provided token represents an ERC20 or the native token reserve
 */
function isNative(Token token) pure returns (bool) {
    return token == NATIVE_TOKEN;
}

/**
 * @dev returns the symbol of the native token/ERC20 token
 */
function symbol(Token token) view returns (string memory) {
    if (isNative(token)) {
        return NATIVE_TOKEN_SYMBOL;
    }
    return toERC20(token).symbol();
}

/**
 * @dev returns the decimals of the native token/ERC20 token
 */
function decimals(Token token) view returns (uint8) {
    if (isNative(token)) {
        return NATIVE_TOKEN_DECIMALS;
    }
    return toERC20(token).decimals();
}

/**
 * @dev returns the balance of the native token/ERC20 token
 */
function balanceOf(Token token, address account) view returns (uint256) {
    if (isNative(token)) {
        return account.balance;
    }
    return toIERC20(token).balanceOf(account);
}

/**
 * @dev transfers a specific amount of the native token/ERC20 token
 */
function safeTransfer(Token token, address to, uint256 amount) {
    if (amount == 0) {
        return;
    }
    if (isNative(token)) {
        payable(to).transfer(amount);
    } else {
        toIERC20(token).safeTransfer(to, amount);
    }
}

/**
 * @dev transfers a specific amount of the native token/ERC20 token from a specific holder using the allowance mechanism
 *
 * note that the function does not perform any action if the native token is provided
 */
function safeTransferFrom(Token token, address from, address to, uint256 amount) {
    if (amount == 0 || isNative(token)) {
        return;
    }
    toIERC20(token).safeTransferFrom(from, to, amount);
}

/**
 * @dev approves a specific amount of the native token/ERC20 token from a specific holder
 *
 * note that the function does not perform any action if the native token is provided
 */
function safeApprove(Token token, address spender, uint256 amount) {
    if (isNative(token)) {
        return;
    }
    toIERC20(token).safeApprove(spender, amount);
}

/**
 * @dev utility function that converts a token to an IERC20
 */
function toIERC20(Token token) pure returns (IERC20) {
    return IERC20(Token.unwrap(token));
}

/**
 * @dev utility function that converts a token to an ERC20
 */
function toERC20(Token token) pure returns (ERC20) {
    return ERC20(Token.unwrap(token));
}
