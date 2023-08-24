// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IStaticOracle } from "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { CarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

import { MockUniswapV3Router } from "../../contracts/helpers/MockUniswapV3Router.sol";
import { MockUniswapV3Factory } from "../../contracts/helpers/MockUniswapV3Factory.sol";
import { MockUniswapV3Oracle } from "../../contracts/helpers/MockUniswapV3Oracle.sol";

import { AccessDenied, InvalidAddress, InvalidFee, InvalidPPBValue, InvalidPeriod } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION, PPB_RESOLUTION } from "../../contracts/utility/Constants.sol";

import { ICarbonPOL } from "../../contracts/pol/interfaces/ICarbonPOL.sol";

import { MathEx } from "../../contracts/utility/MathEx.sol";

import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract CarbonPOLTest is TestFixture {
    using Address for address payable;

    address private bancorNetworkV3;
    MockUniswapV3Router private uniV3Router;
    MockUniswapV3Factory private uniV3Factory;
    MockUniswapV3Oracle private uniV3Oracle;

    uint32 private constant REWARDS_PPM_DEFAULT = 2000;
    uint32 private constant REWARDS_PPM_UPDATED = 3000;

    uint32 private constant MAX_SLIPPAGE_PPM_DEFAULT = 3000;
    uint32 private constant MAX_SLIPPAGE_PPM_UPDATED = 4000;

    uint32 private constant MAX_TRADEABLE_PPB_DEFAULT = 1389;
    uint32 private constant MAX_TRADEABLE_PPB_UPDATED = 2000;

    // Events

    /**
     * @dev triggered after a successful trade is executed
     */
    event TokensTraded(
        address indexed caller,
        Token[] tokens,
        uint24[] poolFees,
        uint256[] tradeAmounts,
        uint256[] rewardAmounts,
        uint256 ethReceived
    );

    /**
     * @dev triggered when the rewards ppm are updated
     */
    event RewardsUpdated(uint32 prevRewardsPPM, uint32 newRewardsPPM);

    /**
     * @dev triggered when the max slippage ppm is updated
     */
    event MaxSlippageUpdated(uint32 prevMaxSlippagePPM, uint32 newMaxSlippagePPM);

    /**
     * @dev triggered when the max tradeable ppb per block is updated
     */
    event MaxTradeableUpdated(uint32 prevMaxTradeablePPB, uint32 newMaxTradeablePPB);

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
        // Deploy Uniswap V3 Factory Mock
        uniV3Factory = deployUniswapV3Factory();
        // Deploy Uniswap V3 Router Mock
        uniV3Router = deployUniswapV3Router(address(uniV3Factory));
        // Deploy Uniswap V3 Oracle Mock
        uniV3Oracle = deployUniswapV3Oracle(address(uniV3Factory));
        // Deploy Carbon POL
        deployCarbonPOL(address(uniV3Router), address(uniV3Factory), address(uniV3Oracle), 30 minutes);
        // Transfer tokens to Carbon POL
        transferTokensToCarbonPOL();
    }

    /**
     * @dev construction tests
     */

    function testShouldRevertWhenDeployingWithInvalidRouterContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonPOL(
            ISwapRouter(address(0)),
            IUniswapV3Factory(address(uniV3Factory)),
            IStaticOracle(address(uniV3Oracle)),
            weth,
            30 minutes
        );
    }

    function testShouldRevertWhenDeployingWithInvalidFactoryContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonPOL(
            ISwapRouter(address(uniV3Router)),
            IUniswapV3Factory(address(0)),
            IStaticOracle(address(uniV3Oracle)),
            weth,
            30 minutes
        );
    }

    function testShouldRevertWhenDeployingWithInvalidOracleContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonPOL(
            ISwapRouter(address(uniV3Router)),
            IUniswapV3Factory(address(uniV3Factory)),
            IStaticOracle(address(0)),
            weth,
            30 minutes
        );
    }

    function testShouldRevertWhenDeployingWithInvalidWethContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonPOL(
            ISwapRouter(address(uniV3Router)),
            IUniswapV3Factory(address(uniV3Factory)),
            IStaticOracle(address(uniV3Oracle)),
            Token.wrap(address(0)),
            30 minutes
        );
    }

    function testShouldRevertWhenDeployingWithInvalidTwapPeriod() public {
        vm.expectRevert(InvalidPeriod.selector);
        new CarbonPOL(
            ISwapRouter(address(uniV3Router)),
            IUniswapV3Factory(address(uniV3Factory)),
            IStaticOracle(address(uniV3Oracle)),
            weth,
            0
        );
    }

    function testShouldBeInitialized() public {
        uint16 version = carbonPOL.version();
        assertEq(version, 1);
    }

    function testShouldntBeAbleToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        carbonPOL.initialize();
    }

    /**
     * @dev rewards ppm tests
     */

    /// @dev test that setRewardsPPM should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheRewardsPPM() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.setRewardsPPM(REWARDS_PPM_UPDATED);
    }

    /// @dev test that setRewardsPPM should revert when a setting to an invalid fee
    function testShouldRevertSettingTheRewardsPPMWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(InvalidFee.selector);
        carbonPOL.setRewardsPPM(PPM_RESOLUTION + 1);
    }

    /// @dev test that setRewardsPPM with the same rewards ppm should be ignored
    function testFailShouldIgnoreSettingTheSameRewardsPPM() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit RewardsUpdated(REWARDS_PPM_DEFAULT, REWARDS_PPM_DEFAULT);
        carbonPOL.setRewardsPPM(REWARDS_PPM_DEFAULT);
    }

    /// @dev test that admin should be able to update the rewards ppm
    function testShouldBeAbleToSetAndUpdateTheRewardsPPM() public {
        vm.startPrank(admin);
        uint32 rewardsPPM = carbonPOL.rewardsPPM();
        assertEq(rewardsPPM, REWARDS_PPM_DEFAULT);

        vm.expectEmit();
        emit RewardsUpdated(REWARDS_PPM_DEFAULT, REWARDS_PPM_UPDATED);
        carbonPOL.setRewardsPPM(REWARDS_PPM_UPDATED);

        rewardsPPM = carbonPOL.rewardsPPM();
        assertEq(rewardsPPM, REWARDS_PPM_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev max slippage ppm tests
     */

    /// @dev test that setMaxSlippagePPM should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheMaxSlippagePPM() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.setMaxSlippagePPM(MAX_SLIPPAGE_PPM_UPDATED);
    }

    /// @dev test that setMaxSlippagePPM should revert when a setting to an invalid value
    function testShouldRevertSettingTheMaxSlippagePPMWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(InvalidFee.selector);
        carbonPOL.setMaxSlippagePPM(PPM_RESOLUTION + 1);
    }

    /// @dev test that setMaxSlippagePPM with the same max slippage ppm should be ignored
    function testFailShouldIgnoreSettingTheSameMaxSlippagePPM() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit MaxSlippageUpdated(MAX_SLIPPAGE_PPM_DEFAULT, MAX_SLIPPAGE_PPM_DEFAULT);
        carbonPOL.setMaxSlippagePPM(MAX_SLIPPAGE_PPM_DEFAULT);
    }

    /// @dev test that admin should be able to update the max slippage ppm
    function testShouldBeAbleToSetAndUpdateTheMaxSlippagePPM() public {
        vm.startPrank(admin);
        uint32 maxSlippagePPM = carbonPOL.maxSlippagePPM();
        assertEq(maxSlippagePPM, MAX_SLIPPAGE_PPM_DEFAULT);

        vm.expectEmit();
        emit MaxSlippageUpdated(MAX_SLIPPAGE_PPM_DEFAULT, MAX_SLIPPAGE_PPM_UPDATED);
        carbonPOL.setMaxSlippagePPM(MAX_SLIPPAGE_PPM_UPDATED);

        maxSlippagePPM = carbonPOL.maxSlippagePPM();
        assertEq(maxSlippagePPM, MAX_SLIPPAGE_PPM_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev max tradeable ppb tests
     */

    /// @dev test that setMaxTradeablePPB should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheMaxTradeablePPB() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.setMaxTradeablePPB(MAX_TRADEABLE_PPB_UPDATED);
    }

    /// @dev test that setMaxTradeablePPB should revert when a setting to an invalid value
    function testShouldRevertSettingTheMaxTradeablePPBWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(InvalidPPBValue.selector);
        carbonPOL.setMaxTradeablePPB(PPB_RESOLUTION + 1);
    }

    /// @dev test that setMaxTradeablePPB with the same max tradeable ppb should be ignored
    function testFailShouldIgnoreSettingTheSameMaxTradeablePPB() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit MaxTradeableUpdated(MAX_TRADEABLE_PPB_DEFAULT, MAX_TRADEABLE_PPB_DEFAULT);
        carbonPOL.setMaxTradeablePPB(MAX_TRADEABLE_PPB_DEFAULT);
    }

    /// @dev test that admin should be able to update the max tradeable ppb
    function testShouldBeAbleToSetAndUpdateTheMaxTradeablePPB() public {
        vm.startPrank(admin);
        uint32 maxTradeablePPB = carbonPOL.maxTradeablePPB();
        assertEq(maxTradeablePPB, MAX_TRADEABLE_PPB_DEFAULT);

        vm.expectEmit();
        emit MaxTradeableUpdated(MAX_TRADEABLE_PPB_DEFAULT, MAX_TRADEABLE_PPB_UPDATED);
        carbonPOL.setMaxTradeablePPB(MAX_TRADEABLE_PPB_UPDATED);

        maxTradeablePPB = carbonPOL.maxTradeablePPB();
        assertEq(maxTradeablePPB, MAX_TRADEABLE_PPB_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev max tradeable tests
     */

    /// @dev test last traded block initializes to 0
    function testLastTradedBlockShouldBeZeroForEachTokenInitially(uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        uint256 lastTradedBlock = carbonPOL.lastTradedBlock(tokens[i]);
        assertEq(lastTradedBlock, 0);
    }

    /// @dev test successful trades reset the last traded block to latest one
    function testSuccessfulTradeShouldResetLastTradedBlockToLatestOne() public {
        // set block.number to 100
        vm.roll(100);
        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 3000;
        poolFees[2] = 500;
        // trade
        carbonPOL.tradeTokens(tokens, poolFees);

        // check which pools exist
        bool[] memory poolExists = new bool[](3);
        poolExists[0] = _poolExists(token1, weth, poolFees[0]);
        poolExists[1] = _poolExists(token2, weth, poolFees[1]);
        poolExists[2] = _poolExists(bnt, weth, poolFees[2]);

        // get last traded blocks for each token
        for (uint i = 0; i < tokens.length; ++i) {
            uint256 lastTradedBlock = carbonPOL.lastTradedBlock(tokens[i]);
            // if pool doesn't exist, last traded block shouldn't change b/c no trade was made
            if (poolExists[i]) {
                assertEq(lastTradedBlock, block.number);
            } else {
                assertEq(lastTradedBlock, 0);
            }
        }
    }

    /// @dev test successful trades reset the max tradeable amount to 0
    function testSuccessfulTradeShouldResetTheMaxTradeableAmount() public {
        // set block.number to 100
        vm.roll(100);
        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 3000;
        poolFees[2] = 500;
        // bnt pool doesn't exist, so cache the max tradeable amount before making the trade
        uint256 maxTradeableAmountPrev = carbonPOL.maxTradeableAmount(bnt);
        // trade
        carbonPOL.tradeTokens(tokens, poolFees);

        // check which pools exist
        bool[] memory poolExists = new bool[](3);
        poolExists[0] = _poolExists(token1, weth, poolFees[0]);
        poolExists[1] = _poolExists(token2, weth, poolFees[1]);
        poolExists[2] = _poolExists(bnt, weth, poolFees[2]);

        // get max tradeable amount for each token
        for (uint i = 0; i < tokens.length; ++i) {
            uint256 maxTradeableAmount = carbonPOL.maxTradeableAmount(tokens[i]);
            // if pool doesn't exist, max tradeable amount shouldn't change b/c no trade was made
            if (poolExists[i]) {
                assertEq(maxTradeableAmount, 0);
            } else {
                assertEq(maxTradeableAmount, maxTradeableAmountPrev);
            }
        }
    }

    /// @dev test max tradeable amount should increase with each block mined
    function testMaxTradeableAmountShouldIncreaseWithEachBlock() public {
        // set block.number to 1
        vm.roll(1);
        uint256 tradeableAmountBefore = carbonPOL.maxTradeableAmount(token1);
        // set block.number to 2
        vm.roll(2);
        uint256 tradeableAmountAfter = carbonPOL.maxTradeableAmount(token1);
        assertGt(tradeableAmountAfter, tradeableAmountBefore);
    }

    /// @dev test max tradeable amount has a max cap of the token balance
    function testMaxTradeableAmountShouldBeCappedAtTokenBalance() public {
        uint256 tokenBalance = token1.balanceOf(address(carbonPOL));
        // blocks mined to reach 100% of balance tradeable = 100 days * 7200 blocks per day = 720000 blocks
        // given 1% increase every 24 hours
        vm.roll(720000);
        uint256 tradeableAmount = carbonPOL.maxTradeableAmount(token1);
        assertEq(tradeableAmount, tokenBalance);
        // assert mining more blocks doesn't change the max tradeable
        vm.roll(820000);
        tradeableAmount = carbonPOL.maxTradeableAmount(token1);
        assertEq(tradeableAmount, tokenBalance);
    }

    /// @dev test proper calculation of max tradeable amount before the first trade for a token
    function testShouldCalculateMaxTradeableProperlyBeforeFirstTrade(uint256 blockNumber) public {
        blockNumber = bound(blockNumber, 1, 100_000);

        // set block to blockNumber
        vm.roll(blockNumber);

        // contract gets deployed at block 1
        uint256 blocksMined = blockNumber - 1;

        // get max tradeable amount
        uint256 tradeableAmount = carbonPOL.maxTradeableAmount(token1);

        // calculate expected max tradeable amount
        uint256 maxTradeablePPBPerBlock = carbonPOL.maxTradeablePPB();
        uint256 maxTradeable = blocksMined * maxTradeablePPBPerBlock;
        uint256 tokenBalance = token1.balanceOf(address(carbonPOL));
        uint256 expectedTradeableAmount = MathEx.mulDivF(tokenBalance, maxTradeable, PPB_RESOLUTION);

        // assert values are equal
        assertEq(tradeableAmount, expectedTradeableAmount);
    }

    /// @dev test proper calculation of max tradeable amount after the first trade for a token
    function testShouldCalculateMaxTradeableProperlyAfterFirstTrade(uint256 blockNumber) public {
        blockNumber = bound(blockNumber, 2, 100_000);

        // set block to blockNumber
        vm.roll(blockNumber);

        Token[] memory tokens = new Token[](1);
        uint24[] memory poolFees = new uint24[](1);
        tokens[0] = token1;
        poolFees[0] = 3000;
        // trade
        carbonPOL.tradeTokens(tokens, poolFees);

        // set block.number to blockNumber * 2
        vm.roll(blockNumber * 2);

        // get blocks mined since last traded block
        uint256 blocksMined = block.number - carbonPOL.lastTradedBlock(token1);

        // get max tradeable amount
        uint256 tradeableAmount = carbonPOL.maxTradeableAmount(token1);

        // calculate expected max tradeable amount
        uint256 maxTradeablePPBPerBlock = carbonPOL.maxTradeablePPB();
        uint256 maxTradeable = blocksMined * maxTradeablePPBPerBlock;
        uint256 tokenBalance = token1.balanceOf(address(carbonPOL));
        uint256 expectedTradeableAmount = MathEx.mulDivF(tokenBalance, maxTradeable, PPB_RESOLUTION);

        // assert values are equal
        assertEq(tradeableAmount, expectedTradeableAmount);
    }

    /**
     * @dev rewards distribution tests
     */

    /// @dev test should distribute rewards to user and swap tokens to ETH if tradeable amount is > 0
    function testShouldDistributeRewardsToUserAndSwapTokensToETHIfTradeableAmountIsAboveZero() public {
        vm.startPrank(admin);

        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 3000;
        poolFees[2] = 3000;

        uint256 rewards = carbonPOL.rewardsPPM();

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(admin);
        balancesBefore[1] = token2.balanceOf(admin);
        balancesBefore[2] = bnt.balanceOf(admin);

        uint256 ethBalanceBefore = address(carbonPOL).balance;

        uint256[] memory expectedUserRewards = new uint256[](3);
        uint256[] memory expectedSwapAmounts = new uint256[](3);

        // set block.number to 10000 so we can trade > 0 amount
        // note that trade amount increases linearly with blocks mined
        vm.roll(10000);

        for (uint256 i = 0; i < 3; ++i) {
            uint256 tradeAmount = carbonPOL.maxTradeableAmount(tokens[i]);
            uint256 reward = (tradeAmount * rewards) / PPM_RESOLUTION;
            expectedUserRewards[i] = reward;
            expectedSwapAmounts[i] = tradeAmount - expectedUserRewards[i];
        }

        // in mock uni router v3, each token swap adds 300e18 tokens to the output
        // we swap tokens to wETH, so the end gain is token (with active pool) count * 300
        uint256 swapGain = 300 ether * 3;
        uint256 expectedEthReceived = expectedSwapAmounts[0] +
            expectedSwapAmounts[1] +
            expectedSwapAmounts[2] +
            swapGain;

        vm.expectEmit();
        emit TokensTraded(admin, tokens, poolFees, expectedSwapAmounts, expectedUserRewards, expectedEthReceived);
        carbonPOL.tradeTokens(tokens, poolFees);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(admin);
        balancesAfter[1] = token2.balanceOf(admin);
        balancesAfter[2] = bnt.balanceOf(admin);
        uint256 ethBalanceAfter = address(carbonPOL).balance;

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        uint256 ethGained = ethBalanceAfter - ethBalanceBefore;

        assertEq(ethGained, expectedEthReceived);
        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should skip tokens for which the pool doesn't exist
    function testShouldSkipTokenIfPoolDoesNotExist() public {
        vm.startPrank(admin);

        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 3000;
        poolFees[2] = 500;

        assertTrue(!_poolExists(bnt, weth, 500));

        uint256 rewards = carbonPOL.rewardsPPM();

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(admin);
        balancesBefore[1] = token2.balanceOf(admin);
        balancesBefore[2] = bnt.balanceOf(admin);

        uint256 ethBalanceBefore = address(carbonPOL).balance;

        uint256[] memory expectedUserRewards = new uint256[](3);
        uint256[] memory expectedSwapAmounts = new uint256[](3);

        // set block.number to 10000 so we can trade > 0 amount
        // note that trade amount increases linearly with blocks mined
        vm.roll(100);

        for (uint256 i = 0; i < 3; ++i) {
            uint256 tradeAmount = _poolExists(tokens[i], weth, poolFees[i])
                ? carbonPOL.maxTradeableAmount(tokens[i])
                : 0;
            uint256 reward = (tradeAmount * rewards) / PPM_RESOLUTION;
            expectedUserRewards[i] = reward;
            expectedSwapAmounts[i] = tradeAmount - expectedUserRewards[i];
        }

        // in mock uni router v3, each token swap adds 300e18 tokens to the output
        // we swap tokens to wETH, so the end gain is token (with active pool) count * 300
        uint256 swapGain = 300 ether * 2;
        uint256 expectedEthReceived = expectedSwapAmounts[0] +
            expectedSwapAmounts[1] +
            expectedSwapAmounts[2] +
            swapGain;

        vm.expectEmit();
        emit TokensTraded(admin, tokens, poolFees, expectedSwapAmounts, expectedUserRewards, expectedEthReceived);
        carbonPOL.tradeTokens(tokens, poolFees);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(admin);
        balancesAfter[1] = token2.balanceOf(admin);
        balancesAfter[2] = bnt.balanceOf(admin);
        uint256 ethBalanceAfter = address(carbonPOL).balance;

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        uint256 ethGained = ethBalanceAfter - ethBalanceBefore;

        assertEq(ethGained, expectedEthReceived);
        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should skip tokens with trade amount = 0
    function testShouldSkipTokensWithTradeAmountEqualToZero(bool fiveBpsFee) public {
        vm.startPrank(admin);

        Token[] memory tokens = new Token[](1);
        uint24[] memory poolFees = new uint24[](1);
        tokens[0] = token1;
        poolFees[0] = 3000;

        // set block.number so that max tradeable amount is > 0
        vm.roll(100);

        uint256 tradeAmountBefore = carbonPOL.maxTradeableAmount(tokens[0]);

        // trade tokens to reset token1 max tradeable amount
        carbonPOL.tradeTokens(tokens, poolFees);

        // expect trade amount for token1 to change to 0
        uint256 tradeAmountAfter = carbonPOL.maxTradeableAmount(tokens[0]);
        assertTrue(tradeAmountBefore != tradeAmountAfter);
        assertEq(tradeAmountAfter, 0);

        // add token2 and bnt to test that we skip token1 when trading
        tokens = new Token[](3);
        poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = fiveBpsFee ? 500 : 3000; // to check pool traded against has no effect on max tradeable
        poolFees[1] = 3000;
        poolFees[2] = 3000;

        uint256 rewards = carbonPOL.rewardsPPM();

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(admin);
        balancesBefore[1] = token2.balanceOf(admin);
        balancesBefore[2] = bnt.balanceOf(admin);

        uint256 ethBalanceBefore = address(carbonPOL).balance;

        uint256[] memory expectedUserRewards = new uint256[](3);
        uint256[] memory expectedSwapAmounts = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            uint256 tradeAmount = carbonPOL.maxTradeableAmount(tokens[i]);
            uint256 reward = (tradeAmount * rewards) / PPM_RESOLUTION;
            expectedUserRewards[i] = reward;
            expectedSwapAmounts[i] = tradeAmount - expectedUserRewards[i];
        }

        // assert that token1 expected trade amount is 0
        assertEq(expectedSwapAmounts[0], 0);

        // in mock uni router v3, each token swap adds 300e18 tokens to the output
        // we swap tokens to wETH, so the end gain is token (with active pool and > 0 trade amount) count * 300
        uint256 swapGain = 300 ether * 2;
        uint256 expectedEthReceived = expectedSwapAmounts[0] +
            expectedSwapAmounts[1] +
            expectedSwapAmounts[2] +
            swapGain;

        vm.expectEmit();
        emit TokensTraded(admin, tokens, poolFees, expectedSwapAmounts, expectedUserRewards, expectedEthReceived);
        carbonPOL.tradeTokens(tokens, poolFees);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(admin);
        balancesAfter[1] = token2.balanceOf(admin);
        balancesAfter[2] = bnt.balanceOf(admin);
        uint256 ethBalanceAfter = address(carbonPOL).balance;

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        uint256 ethGained = ethBalanceAfter - ethBalanceBefore;

        assertEq(ethGained, expectedEthReceived);
        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should approve tokens to uni v3 router if allowance is less than swap amount
    function testShouldApproveTokensToUniV3RouterIfAllowanceIsLessThanSwapAmount() public {
        vm.startPrank(user1);

        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 3000;
        poolFees[2] = 3000;

        // set block.number to 10000 so we have > 0 trade amounts
        vm.roll(10000);

        for (uint256 i = 0; i < tokens.length; ++i) {
            Token token = tokens[i];
            uint256 approveAmount = type(uint256).max;
            uint256 allowance = token.allowance(address(carbonVortex), address(uniV3Router));
            // test should approve max uint256 if allowance is 0
            if (allowance == 0) {
                vm.expectEmit(true, true, true, true, Token.unwrap(token));
                emit Approval(address(carbonPOL), address(uniV3Router), approveAmount);
                Token[] memory _tokens = new Token[](1);
                _tokens[0] = token;
                uint24[] memory _poolFees = new uint24[](1);
                _poolFees[0] = poolFees[i];
                carbonPOL.tradeTokens(_tokens, _poolFees);
            }
        }

        vm.stopPrank();
    }

    /// @dev test shouldn't approve tokens to uni v3 router if current allowance is more than swap amount
    function testFailShouldntApproveTokensToUniV3RouterIfAllowanceIsMoreThanSwapAmount() public {
        vm.startPrank(user1);

        // set block.number to 10000 so we have > 0 trade amounts
        vm.roll(10000);

        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 3000;
        poolFees[2] = 3000;
        // trade tokens once so that tokens get approved
        carbonPOL.tradeTokens(tokens, poolFees);

        uint256 approveAmount = type(uint256).max;
        vm.expectEmit();
        emit Approval(address(carbonVortex), bancorNetworkV3, approveAmount);
        // check we don't approve again in the second trade
        carbonPOL.tradeTokens(tokens, poolFees);
        vm.stopPrank();
    }

    /**
     * @dev trade validations
     */

    /// @dev test trade should revert if min output amount is not enough due to slippage
    function testShouldRevertIfMinOutputAmountIsNotEnoughDueToSlippage(
        uint32 maxSlippagePPM,
        uint256 swapSlippagePPM
    ) public {
        maxSlippagePPM = uint32(bound(maxSlippagePPM, 1000, 900_000));
        swapSlippagePPM = bound(swapSlippagePPM, 1000, 900_000);
        // set swap slippage to a value higher than max slippage ppm
        vm.assume(swapSlippagePPM > maxSlippagePPM);

        Token[] memory tokens = new Token[](1);
        uint24[] memory poolFees = new uint24[](1);
        tokens[0] = token1;
        poolFees[0] = 3000;

        // set block.number to 100
        vm.roll(100);

        vm.prank(admin);
        // set max slippage to maxSlippagePPM
        carbonPOL.setMaxSlippagePPM(maxSlippagePPM);

        // get trade amount for token
        uint256 tradeAmount = carbonPOL.maxTradeableAmount(token1);

        // set swap output amount to less than max slippage ppm
        uint256 outputAmount = MathEx.mulDivF(tradeAmount, swapSlippagePPM, PPM_RESOLUTION);
        uniV3Router.setProfitAndOutputAmount(false, outputAmount);

        // set oracle price to exactly 1 - so that tokens are exchangeable 1:1
        uniV3Oracle.setPriceForPool(token1, weth, 3000, 1e18);

        // trade
        vm.prank(user1);
        vm.expectRevert("Too little received");
        carbonPOL.tradeTokens(tokens, poolFees);
    }

    /// @dev test trade should revert if min output amount is not enough due to amount quoted by the oracle
    function testShouldRevertIfMinOutputAmountIsNotEnoughDueToOracleQuote() public {
        Token[] memory tokens = new Token[](1);
        uint24[] memory poolFees = new uint24[](1);
        tokens[0] = token1;
        poolFees[0] = 3000;

        // set block.number to 100
        vm.roll(100);

        vm.prank(admin);
        // set max slippage to 0%
        carbonPOL.setMaxSlippagePPM(0);

        // get trade amount for token
        uint256 tradeAmount = carbonPOL.maxTradeableAmount(token1);

        // set oracle price to exactly 0.1, so 1 token1 = 0.1 weth
        uint256 oraclePrice = 1e17;
        uniV3Oracle.setPriceForPool(token1, weth, 3000, oraclePrice);

        // set swap output amount to less than input by 91% of tradeAmount
        // this output amount leads to 1 token = 0.09 weth
        uint256 outputAmount = MathEx.mulDivF(tradeAmount, 910_000, PPM_RESOLUTION);
        uniV3Router.setProfitAndOutputAmount(false, outputAmount);

        // trade
        vm.prank(user1);
        vm.expectRevert("Too little received");
        carbonPOL.tradeTokens(tokens, poolFees);
    }

    /// @dev test should revert if any of the tokens sent has duplicates
    function testShouldRevertIfAnyOfTheTokensSentHasDuplicates() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = bnt;
        tokens[1] = nonTradeableToken;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 500;
        poolFees[2] = 500;
        vm.expectRevert(ICarbonPOL.DuplicateToken.selector);
        carbonPOL.tradeTokens(tokens, poolFees);
    }

    /// @dev test should revert if tokens and fees sent are with different lengths
    function testShouldRevertIfTokensAndFeesLengthsDontMatch() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](2);
        tokens[0] = bnt;
        tokens[1] = nonTradeableToken;
        tokens[2] = bnt;
        poolFees[0] = 3000;
        poolFees[1] = 500;
        vm.expectRevert(ICarbonPOL.TokenPoolFeesLengthMismatch.selector);
        carbonPOL.tradeTokens(tokens, poolFees);
    }

    /// @dev test should revert if any of the tokens sent is the native token or weth
    function testShouldRevertIfAnyOfTheTokensSentIsNativeTokenOrWeth() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](3);
        uint24[] memory poolFees = new uint24[](3);
        tokens[0] = bnt;
        tokens[1] = NATIVE_TOKEN;
        tokens[2] = token2;
        poolFees[0] = 3000;
        poolFees[1] = 500;
        poolFees[2] = 500;
        vm.expectRevert(ICarbonPOL.InvalidToken.selector);
        carbonPOL.tradeTokens(tokens, poolFees);
        // change token 1 to weth
        tokens[1] = weth;
        vm.expectRevert(ICarbonPOL.InvalidToken.selector);
        carbonPOL.tradeTokens(tokens, poolFees);
    }

    /// @dev test should revert if no tokens are sent
    function testShouldRevertIfNoTokensAreSent() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](0);
        uint24[] memory poolFees = new uint24[](0);
        vm.expectRevert(ICarbonPOL.InvalidTokenLength.selector);
        carbonPOL.tradeTokens(tokens, poolFees);
    }

    /**
     * @dev helper function to check whether a given pool exists in Uni V3
     */
    function _poolExists(Token token0, Token token1, uint24 poolFee) private view returns (bool) {
        return uniV3Factory.getPool(Token.unwrap(token0), Token.unwrap(token1), poolFee) != address(0);
    }
}
