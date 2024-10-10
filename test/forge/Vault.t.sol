// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { Utilities } from "./Utilities.t.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Vault } from "../../contracts/vault/Vault.sol";
import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";
import { AccessDenied, InvalidAddress } from "../../contracts/utility/Utils.sol";
import { TestERC20Token } from "../../contracts/helpers/TestERC20Token.sol";
import { TestReentrancyVault } from "../../contracts/helpers/TestReentrancyVault.sol";

contract VaultTest is Test {
    using Address for address payable;

    bytes32 private constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 private constant ROLE_ASSET_MANAGER = keccak256("ROLE_ASSET_MANAGER");
    uint256 private constant MAX_WITHDRAW_AMOUNT = 100_000_000 ether;

    Utilities private utils;
    Vault private vault;
    ProxyAdmin private proxyAdmin;
    TestERC20Token private token;

    address payable[] private users;
    address payable private admin;
    address payable private user1;
    address payable private user2;

    /**
     * @dev triggered when tokens have been withdrawn from the vault
     */
    event FundsWithdrawn(Token indexed token, address indexed caller, address indexed target, uint256 amount);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        utils = new Utilities();
        // create 4 users
        users = utils.createUsers(3);
        admin = users[0];
        user1 = users[1];
        user2 = users[2];

        // deploy contracts from admin
        vm.startPrank(admin);
        vault = new Vault();

        // deploy proxy admin
        proxyAdmin = new ProxyAdmin();

        // deploy test token
        token = new TestERC20Token("TKN1", "TKN1", 1_000_000_000 ether);

        // transfer some tokens to the vault
        token.transfer(address(vault), MAX_WITHDRAW_AMOUNT);
        // transfer eth to the vault
        vm.deal(address(vault), MAX_WITHDRAW_AMOUNT);

        // set user1 to be the asset manager
        vault.grantRole(ROLE_ASSET_MANAGER, user1);

        vm.stopPrank();
    }

    /**
     * @dev construction tests
     */

    /// @dev test should be initialized properly
    function testShouldBeInitializedProperly() public view {
        assertEq(ROLE_ADMIN, vault.roleAdmin());
        assertEq(ROLE_ASSET_MANAGER, vault.roleAssetManager());

        assertEq(admin, vault.getRoleMember(ROLE_ADMIN, 0));
        assertEq(user1, vault.getRoleMember(ROLE_ASSET_MANAGER, 0));

        assertEq(1, vault.getRoleMemberCount(ROLE_ADMIN));
        assertEq(1, vault.getRoleMemberCount(ROLE_ASSET_MANAGER));
    }

    /// @dev test should revert when attempting to withdraw funds without the asset manager role
    function testShouldRevertWhenAttemptingToWithdrawFundsWithoutTheAssetManagerRole() public {
        uint256 withdrawAmount = 1000;
        vm.prank(user2);
        vm.expectRevert(AccessDenied.selector);
        vault.withdrawFunds(Token.wrap(address(token)), user2, withdrawAmount);
    }

    /// @dev test should revert when attempting to withdraw funds to an invalid address
    function testShouldRevertWhenAttemptingToWithdrawFundsToAnInvalidAddress() public {
        uint256 withdrawAmount = 1000;
        vm.prank(user1);
        vm.expectRevert(InvalidAddress.selector);
        vault.withdrawFunds(Token.wrap(address(token)), payable(address(0)), withdrawAmount);
    }

    /// @dev test admin should be able to grant the asset manager role
    function testAdminShouldBeAbleToGrandTheAssetManagerRole() public {
        vm.prank(admin);
        // grant asset manager role to user2
        vault.grantRole(ROLE_ASSET_MANAGER, user2);
        // test user2 has asset manager role
        assertEq(user2, vault.getRoleMember(ROLE_ASSET_MANAGER, 1));
    }

    /// @dev test admin should be able to grant the asset manager role
    function testAdminShouldBeAbleToRevokeTheAssetManagerRole() public {
        // assert there is only one asset manager role and that is user1
        assertEq(user1, vault.getRoleMember(ROLE_ASSET_MANAGER, 0));
        assertEq(1, vault.getRoleMemberCount(ROLE_ASSET_MANAGER));

        vm.startPrank(admin);
        // revoke asset manager role from user1
        vault.revokeRole(ROLE_ASSET_MANAGER, user1);
        // test user1 doesn't have asset manager role
        assertEq(0, vault.getRoleMemberCount(ROLE_ASSET_MANAGER));
    }

    /// @dev test addresses with the asset manager role should be able to withdraw tokens
    function testAssetManagerShouldBeAbleToWithdrawTokens(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 0, MAX_WITHDRAW_AMOUNT);

        uint256 balanceBeforeVault = token.balanceOf(address(vault));
        uint256 balanceBeforeUser2 = token.balanceOf(user2);

        vm.prank(user1);
        // withdraw token to user2
        vault.withdrawFunds(Token.wrap(address(token)), user2, withdrawAmount);

        uint256 balanceAfterVault = token.balanceOf(address(vault));
        uint256 balanceAfterUser2 = token.balanceOf(user2);

        uint256 balanceWithdrawn = balanceBeforeVault - balanceAfterVault;
        uint256 balanceGainUser2 = balanceAfterUser2 - balanceBeforeUser2;

        assertEq(balanceWithdrawn, withdrawAmount);
        assertEq(balanceGainUser2, withdrawAmount);
    }

    /// @dev test addresses with the asset manager role should be able to withdraw the native token
    function testAssetManagerShouldBeAbleToWithdrawNativeToken(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 0, MAX_WITHDRAW_AMOUNT);

        uint256 balanceBeforeVault = address(vault).balance;
        uint256 balanceBeforeUser2 = user2.balance;

        vm.prank(user1);
        // withdraw native token to user2
        vault.withdrawFunds(NATIVE_TOKEN, user2, withdrawAmount);

        uint256 balanceAfterVault = address(vault).balance;
        uint256 balanceAfterUser2 = user2.balance;

        uint256 balanceWithdrawn = balanceBeforeVault - balanceAfterVault;
        uint256 balanceGainUser2 = balanceAfterUser2 - balanceBeforeUser2;

        assertEq(balanceWithdrawn, withdrawAmount);
        assertEq(balanceGainUser2, withdrawAmount);
    }

    /// @dev test withdrawing funds should emit event
    function testWithdrawingFundsShouldEmitEvent() public {
        uint256 withdrawAmount = 1000;
        vm.prank(user1);
        vm.expectEmit();
        emit FundsWithdrawn(Token.wrap(address(token)), user1, user2, withdrawAmount);
        // withdraw token to user2
        vault.withdrawFunds(Token.wrap(address(token)), user2, withdrawAmount);
    }

    /// @dev test withdrawing funds shouldn't emit event if withdrawing zero amount
    function testFailWithdrawingFundsShouldnEmitEventIfWithdrawingZeroAmount() public {
        uint256 withdrawAmount = 0;
        vm.prank(user1);
        vm.expectEmit();
        emit FundsWithdrawn(Token.wrap(address(token)), user1, user2, withdrawAmount);
        // withdraw token to user2
        vault.withdrawFunds(Token.wrap(address(token)), user2, withdrawAmount);
    }

    /**
     * @dev test that fund withdrawal should revert if reentrancy is attempted
     */
    function testShouldRevertFundWithdrawalIfReentrancyIsAttempted() public {
        vm.startPrank(admin);
        TestReentrancyVault testReentrancy = new TestReentrancyVault(vault, Token.wrap(address(token)));
        // grant withdrawal role to testReentrancy contract
        vault.grantRole(ROLE_ASSET_MANAGER, address(testReentrancy));

        uint256 withdrawAmount = 1000;
        // reverts in "unsafeTransfer" in withdrawFunds - which uses OZ's Address "sendValue" function
        vm.expectRevert("Address: unable to send value, recipient may have reverted");
        testReentrancy.tryReenterWithdrawFunds(NATIVE_TOKEN, payable(address(testReentrancy)), withdrawAmount);
        vm.stopPrank();
    }
}
