// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { CarbonVortex } from "../../contracts/vortex/CarbonVortex.sol";
import { TestReenterCarbonVortex } from "../../contracts/helpers/TestReenterCarbonVortex.sol";

import { AccessDenied, InvalidAddress, InvalidFee } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";

import { ICarbonController } from "../../contracts/carbon/interfaces/ICarbonController.sol";
import { ICarbonVortex } from "../../contracts/vortex/interfaces/ICarbonVortex.sol";
import { IBancorNetwork } from "../../contracts/vortex/CarbonVortex.sol";

import { Token, toIERC20, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract CarbonVortexTest is TestFixture {
    using Address for address payable;

    address private bancorNetworkV3;

    uint256 private constant REWARDS_PPM_DEFAULT = 100_000;
    uint256 private constant REWARDS_PPM_UPDATED = 110_000;

    // Events
    /**
     * @dev triggered after a successful burn is executed
     */
    event TokensBurned(address indexed caller, Token[] tokens, uint256[] rewardAmounts, uint256 burnAmount);

    /**
     * @dev triggered when the rewards ppm are updated
     */
    event RewardsUpdated(uint256 prevRewardsPPM, uint256 newRewardsPPM);

    /**
     * @dev triggered when fees are withdrawn
     */
    event FeesWithdrawn(Token indexed token, address indexed recipient, uint256 indexed amount, address sender);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
        // Deploy Bancor Network V3 mock
        bancorNetworkV3 = address(deployBancorNetworkV3Mock());
        // Deploy Carbon Vortex
        deployCarbonVortex(address(carbonController), bancorNetworkV3);
        // Transfer tokens to Carbon Controller
        transferTokensToCarbonController();
    }

    /**
     * @dev construction tests
     */

    function testShouldRevertWhenDeployingWithInvalidBNTContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonVortex(
            Token.wrap(address(0)),
            ICarbonController(address(carbonController)),
            IBancorNetwork(bancorNetworkV3)
        );
    }

    function testShouldRevertWhenDeployingWithInvalidCarbonControllerContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonVortex(bnt, ICarbonController(address(0)), IBancorNetwork(bancorNetworkV3));
    }

    function testShouldRevertWhenDeployingWithInvalidBancorV3Contract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonVortex(bnt, ICarbonController(address(carbonController)), IBancorNetwork(address(0)));
    }

    function testShouldBeInitialized() public {
        uint16 version = carbonVortex.version();
        assertEq(version, 2);
    }

    function testShouldntBeAbleToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        carbonVortex.initialize();
    }

    /**
     * @dev rewards ppm tests
     */

    /// @dev test that setRewardsPPM should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheRewardsPPM() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setRewardsPPM(REWARDS_PPM_UPDATED);
    }

    /// @dev test that setRewardsPPM should revert when a setting to an invalid fee
    function testShouldRevertSettingTheRewardsPPMWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(InvalidFee.selector);
        carbonVortex.setRewardsPPM(PPM_RESOLUTION + 1);
    }

    /// @dev test that setRewardsPPM with the same rewards pom should be ignored
    function testFailShouldIgnoreSettingTheSameRewardsPPM() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit RewardsUpdated(REWARDS_PPM_DEFAULT, REWARDS_PPM_DEFAULT);
        carbonVortex.setRewardsPPM(REWARDS_PPM_DEFAULT);
    }

    /// @dev test that admin should be able to update the rewards ppm
    function testShouldBeAbleToSetAndUpdateTheRewardsPPM() public {
        vm.startPrank(admin);
        uint256 rewardsPPM = carbonVortex.rewardsPPM();
        assertEq(rewardsPPM, REWARDS_PPM_DEFAULT);

        vm.expectEmit();
        emit RewardsUpdated(REWARDS_PPM_DEFAULT, REWARDS_PPM_UPDATED);
        carbonVortex.setRewardsPPM(REWARDS_PPM_UPDATED);

        rewardsPPM = carbonVortex.rewardsPPM();
        assertEq(rewardsPPM, REWARDS_PPM_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev rewards distribution and bnt burn tests
     */

    /// @dev test should distribute rewards to user and burn bnt with token input being BNT
    function testShouldDistributeRewardsToUserAndBurnWithTokenInputAsBNT() public {
        vm.startPrank(admin);
        uint256 amount = 50 ether;
        carbonController.testSetAccumulatedFees(bnt, amount);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256 balanceBefore = bnt.balanceOf(admin);
        uint256 supplyBefore = toIERC20(bnt).totalSupply();

        Token[] memory tokens = new Token[](1);
        tokens[0] = bnt;
        uint256[] memory expectedUserRewards = new uint256[](1);

        // we don't convert bnt, so we expect to get 10% of 50 BNT
        expectedUserRewards[0] = (amount * rewards) / PPM_RESOLUTION;
        uint256 expectedBntBurned = amount - expectedUserRewards[0];

        vm.expectEmit();
        emit TokensBurned(admin, tokens, expectedUserRewards, expectedBntBurned);
        carbonVortex.execute(tokens);

        uint256 balanceAfter = bnt.balanceOf(admin);
        uint256 supplyAfter = toIERC20(bnt).totalSupply();

        uint256 bntGain = balanceAfter - balanceBefore;
        uint256 supplyBurned = supplyBefore - supplyAfter;

        assertEq(bntGain, expectedUserRewards[0]);
        assertEq(supplyBurned, expectedBntBurned);

        vm.stopPrank();
    }

    /// @dev test should distribute rewards to user and burn bnt if fees have accumulated
    function testShouldDistributeRewardsToUserAndBurnIfFeesHaveAccumulated() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;
        tokenAmounts[2] = 10 ether;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1]);
        carbonController.testSetAccumulatedFees(NATIVE_TOKEN, tokenAmounts[2]);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(admin);
        balancesBefore[1] = token2.balanceOf(admin);
        balancesBefore[2] = admin.balance;

        uint256 supplyBefore = toIERC20(bnt).totalSupply();

        uint256[] memory expectedUserRewards = new uint256[](3);
        uint256[] memory expectedSwapAmounts = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            uint256 reward = (tokenAmounts[i] * rewards) / PPM_RESOLUTION;
            expectedUserRewards[i] = reward;
            expectedSwapAmounts[i] = tokenAmounts[i] - expectedUserRewards[i];
        }

        // in mock bancor network v3, each token swap adds 300e18 tokens to the output
        // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
        uint256 swapGain = 300 ether * 3;
        uint256 expectedBntBurned = expectedSwapAmounts[0] + expectedSwapAmounts[1] + expectedSwapAmounts[2] + swapGain;

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        vm.expectEmit();
        emit TokensBurned(admin, tokens, expectedUserRewards, expectedBntBurned);
        carbonVortex.execute(tokens);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(admin);
        balancesAfter[1] = token2.balanceOf(admin);
        balancesAfter[2] = admin.balance;
        uint256 supplyAfter = toIERC20(bnt).totalSupply();

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        uint256 supplyBurned = supplyBefore - supplyAfter;

        assertEq(supplyBurned, expectedBntBurned);
        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should distribute rewards to user and burn bnt if carbonVortex has token balance
    function testShouldDistributeRewardsToUserAndBurnIfContractHasTokenBalance() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;
        tokenAmounts[2] = 10 ether;

        token1.safeTransfer(address(carbonVortex), tokenAmounts[0]);
        token2.safeTransfer(address(carbonVortex), tokenAmounts[1]);
        payable(address(carbonVortex)).sendValue(tokenAmounts[2]);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(admin);
        balancesBefore[1] = token2.balanceOf(admin);
        balancesBefore[2] = admin.balance;

        uint256 supplyBefore = toIERC20(bnt).totalSupply();

        uint256[] memory expectedUserRewards = new uint256[](3);
        uint256[] memory expectedSwapAmounts = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            uint256 reward = (tokenAmounts[i] * rewards) / PPM_RESOLUTION;
            expectedUserRewards[i] = reward;
            expectedSwapAmounts[i] = tokenAmounts[i] - expectedUserRewards[i];
        }

        // in mock bancor network v3, each token swap adds 300e18 tokens to the output
        // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
        uint256 swapGain = 300 ether * 3;
        uint256 expectedBntBurned = expectedSwapAmounts[0] + expectedSwapAmounts[1] + expectedSwapAmounts[2] + swapGain;

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        vm.expectEmit();
        emit TokensBurned(admin, tokens, expectedUserRewards, expectedBntBurned);
        carbonVortex.execute(tokens);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(admin);
        balancesAfter[1] = token2.balanceOf(admin);
        balancesAfter[2] = admin.balance;
        uint256 supplyAfter = toIERC20(bnt).totalSupply();

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        uint256 supplyBurned = supplyBefore - supplyAfter;

        assertEq(supplyBurned, expectedBntBurned);
        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should distribute rewards to user and burn bnt if fees have accumulated and carbon vortex has token balance
    function testShouldDistributeRewardsToUserAndBurnForTokenBalanceAndAccumulatedFees() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0] / 2);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1] / 2);
        carbonController.testSetAccumulatedFees(NATIVE_TOKEN, tokenAmounts[2] / 2);

        token1.safeTransfer(address(carbonVortex), tokenAmounts[0] / 2);
        token2.safeTransfer(address(carbonVortex), tokenAmounts[1] / 2);
        payable(address(carbonVortex)).sendValue(tokenAmounts[2] / 2);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(admin);
        balancesBefore[1] = token2.balanceOf(admin);
        balancesBefore[2] = admin.balance;

        uint256 supplyBefore = toIERC20(bnt).totalSupply();

        uint256[] memory expectedUserRewards = new uint256[](3);
        uint256[] memory expectedSwapAmounts = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            uint256 reward = (tokenAmounts[i] * rewards) / PPM_RESOLUTION;
            expectedUserRewards[i] = reward;
            expectedSwapAmounts[i] = tokenAmounts[i] - expectedUserRewards[i];
        }

        // in mock bancor network v3, each token swap adds 300e18 tokens to the output
        // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
        uint256 swapGain = 300 ether * 3;
        uint256 expectedBntBurned = expectedSwapAmounts[0] + expectedSwapAmounts[1] + expectedSwapAmounts[2] + swapGain;

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        vm.expectEmit();
        emit TokensBurned(admin, tokens, expectedUserRewards, expectedBntBurned);
        carbonVortex.execute(tokens);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(admin);
        balancesAfter[1] = token2.balanceOf(admin);
        balancesAfter[2] = admin.balance;
        uint256 supplyAfter = toIERC20(bnt).totalSupply();

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        uint256 supplyBurned = supplyBefore - supplyAfter;

        assertEq(supplyBurned, expectedBntBurned);
        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /**
     * @dev execute function tests
     */

    /// @dev test should withdraw fees from CarbonController on calling execute
    function testShouldWithdrawFeesOnExecute() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], tokenAmounts[i]);

            vm.expectEmit();
            emit FeesWithdrawn(tokens[i], address(carbonVortex), tokenAmounts[i], address(carbonVortex));
            carbonVortex.execute(tokens);
        }
        vm.stopPrank();
    }

    /// @dev test should emit TokensBurned event on successful burn
    function testShouldEmitEventOnSuccessfulBurn() public {
        vm.startPrank(admin);
        uint256 amount = 50 ether;
        carbonController.testSetAccumulatedFees(bnt, amount);

        uint256 rewards = carbonVortex.rewardsPPM();

        Token[] memory tokens = new Token[](1);
        tokens[0] = bnt;
        uint256[] memory expectedUserRewards = new uint256[](1);

        // we don't convert bnt, so we expect to get 10% of 50 BNT
        expectedUserRewards[0] = (amount * rewards) / PPM_RESOLUTION;
        uint256 expectedBntBurned = amount - expectedUserRewards[0];

        vm.expectEmit();
        emit TokensBurned(admin, tokens, expectedUserRewards, expectedBntBurned);
        carbonVortex.execute(tokens);
    }

    /// @dev test shouldn't emit TokensBurned event on burn with zero amount
    function testFailShouldntEmitEventOnBurnWithZeroAmount() public {
        vm.startPrank(admin);
        uint256 amount = 0;
        carbonController.testSetAccumulatedFees(bnt, amount);

        uint256 rewards = carbonVortex.rewardsPPM();

        Token[] memory tokens = new Token[](1);
        tokens[0] = bnt;
        uint256[] memory expectedUserRewards = new uint256[](1);

        // we don't convert bnt, so we expect to get 10% of 50 BNT
        expectedUserRewards[0] = (amount * rewards) / PPM_RESOLUTION;
        uint256 expectedBntBurned = amount - expectedUserRewards[0];

        vm.expectEmit();
        emit TokensBurned(admin, tokens, expectedUserRewards, expectedBntBurned);
        carbonVortex.execute(tokens);
    }

    /// @dev test should increase total burned amount on calling burn
    function testShouldCorrectlyIncreaseTotalBurnedAmountOnBurn() public {
        vm.startPrank(admin);
        uint256 amount = 50 ether;
        carbonController.testSetAccumulatedFees(bnt, amount);

        uint256 rewards = carbonVortex.rewardsPPM();

        // we don't convert bnt, so we expect to get 10% of 50 BNT
        uint256 rewardAmount = (amount * rewards) / PPM_RESOLUTION;
        uint256 burnAmount = amount - rewardAmount;

        Token[] memory tokens = new Token[](1);
        tokens[0] = bnt;

        uint256 totalBurnedBefore = carbonVortex.totalBurned();

        carbonVortex.execute(tokens);

        uint256 totalBurnedAfter = carbonVortex.totalBurned();

        assertEq(totalBurnedBefore + burnAmount, totalBurnedAfter);
    }

    /// @dev test should correctly update available tokens on burn
    function testShouldCorrectlyUpdateAvailableTokensOnBurn() public {
        vm.startPrank(admin);
        // expect fee amount to be 0 at the beginning
        uint256 feeAmountBefore = carbonVortex.availableTokens(bnt);
        assertEq(feeAmountBefore, 0);

        // set accumulated fees
        uint256[] memory feeAmounts = new uint256[](2);
        feeAmounts[0] = 50 ether;
        feeAmounts[1] = 30 ether;
        carbonController.testSetAccumulatedFees(bnt, feeAmounts[0]);
        // transfer tokens to contract
        bnt.safeTransfer(address(carbonVortex), feeAmounts[1]);

        uint256 expectedFeeAmount = feeAmounts[0] + feeAmounts[1];
        uint256 actualFeeAmount = carbonVortex.availableTokens(bnt);

        assertEq(expectedFeeAmount, actualFeeAmount);

        Token[] memory tokens = new Token[](1);
        tokens[0] = bnt;
        carbonVortex.execute(tokens);

        // expect fee amount to be 0 after
        uint256 feeAmountAfter = carbonVortex.availableTokens(bnt);
        assertEq(feeAmountAfter, 0);

        vm.stopPrank();
    }

    /// @dev test should skip tokens which don't have accumulated fees on calling execute
    function testShouldSkipTokensWhichDontHaveAccumulatedFees() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;
        tokenAmounts[2] = 0;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(bnt, tokenAmounts[1]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[2]);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256[] memory rewardAmounts = new uint256[](3);
        uint256[] memory swapAmounts = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            rewardAmounts[i] = (tokenAmounts[i] * rewards) / PPM_RESOLUTION;
            swapAmounts[i] = tokenAmounts[i] - rewardAmounts[i];
        }

        // we don't convert bnt, so we expect to get 10% of 50 BNT
        uint256 swapGain = 300 ether;
        uint256 burnAmount = swapAmounts[0] + swapAmounts[1] + swapGain;

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = bnt;
        tokens[2] = token2;

        vm.expectEmit();
        emit TokensBurned(admin, tokens, rewardAmounts, burnAmount);
        carbonVortex.execute(tokens);

        vm.stopPrank();
    }

    /// @dev test should approve tokens to bancor network v3 if allowance is less than swap amount
    function testShouldApproveTokensToBancorNetworkV3IfAllowanceIsLessThanSwapAmount() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;

        Token[] memory tokens = new Token[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1]);

        for (uint256 i = 0; i < tokens.length; ++i) {
            Token token = tokens[i];
            uint256 approveAmount = type(uint256).max;
            uint256 allowance = token.allowance(address(carbonVortex), bancorNetworkV3);
            // test should approve max uint256 if allowance is 0
            if (allowance == 0) {
                vm.expectEmit(true, true, true, true, Token.unwrap(token));
                emit Approval(address(carbonVortex), bancorNetworkV3, approveAmount);
                Token[] memory _tokens = new Token[](1);
                _tokens[0] = token;
                carbonVortex.execute(_tokens);
            }
        }

        vm.stopPrank();
    }

    /// @dev test shouldn't approve tokens to bancor network v3 if current allowance is more than swap amount
    function testFailShouldntApproveTokensToBancorNetworkV3IfAllowanceIsMoreThanSwapAmount() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;

        Token[] memory tokens = new Token[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1]);
        // execute burn once so that tokens get approved
        carbonVortex.execute(tokens);

        // test there is no second approval
        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1]);

        uint256 approveAmount = type(uint256).max;
        vm.expectEmit();
        emit Approval(address(carbonVortex), bancorNetworkV3, approveAmount);
        carbonVortex.execute(tokens);
        vm.stopPrank();
    }

    /// @dev test should revert if any of the tokens sent is not tradeable on bancor network v3
    function testShouldRevertIfAnyOfTheTokensSentIsNotTradeableOnBancorNetworkV3() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;

        Token[] memory tokens = new Token[](2);
        tokens[0] = bnt;
        tokens[1] = nonTradeableToken;

        carbonController.testSetAccumulatedFees(bnt, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(nonTradeableToken, tokenAmounts[1]);
        vm.expectRevert(ICarbonVortex.InvalidToken.selector);
        carbonVortex.execute(tokens);
        vm.stopPrank();
    }

    /// @dev test should revert if any of the tokens sent has duplicates
    function testShouldRevertIfAnyOfTheTokensSentHasDuplicates() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](3);
        tokens[0] = bnt;
        tokens[1] = nonTradeableToken;
        tokens[2] = bnt;
        vm.expectRevert(ICarbonVortex.DuplicateToken.selector);
        carbonVortex.execute(tokens);
    }

    /// @dev test should revert if any of the tokens sent doesn't exist
    function testShouldRevertIfAnyOfTheTokensSentDoesntExist() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](3);
        tokens[0] = bnt;
        tokens[1] = Token.wrap(address(0));
        tokens[2] = token2;
        vm.expectRevert(ICarbonVortex.InvalidToken.selector);
        carbonVortex.execute(tokens);
    }

    /// @dev test should revert if no tokens are sent
    function testShouldRevertIfNoTokensAreSent() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](0);
        vm.expectRevert(ICarbonVortex.InvalidTokenLength.selector);
        carbonVortex.execute(tokens);
    }

    /// @dev test should revert if reentrancy is attempted
    function testShouldRevertIfReentrancyIsAttempted() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        // set the accumulated fees
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], tokenAmounts[i]);
        }

        // deploy carbonVortex reentrancy contract
        TestReenterCarbonVortex testReentrancy = new TestReenterCarbonVortex(carbonVortex);
        // expect execute to revert
        // reverts in "sendValue" in _allocateRewards in carbonVortex
        vm.expectRevert("Address: unable to send value, recipient may have reverted");
        testReentrancy.tryReenterCarbonVortex(tokens);
        vm.stopPrank();
    }
}
