// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.sol";
import { TestCaseParser } from "./TestCaseParser.sol";

import { Order, Strategy, TradeAction, Strategies } from "../../contracts/carbon/Strategies.sol";

import { ZeroValue, InvalidAddress } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";
import { MathEx } from "../../contracts/utility/MathEx.sol";

import { CarbonController } from "../../contracts/carbon/CarbonController.sol";
import { Strategies } from "../../contracts/carbon/Strategies.sol";
import { Pair } from "../../contracts/carbon/Pairs.sol";
import { TestERC20FeeOnTransfer } from "../../contracts/helpers/TestERC20FeeOnTransfer.sol";

import { Token, toIERC20, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract TradingTest is TestFixture {
    using Address for address payable;

    // Test case parser helper
    TestCaseParser private testCaseParser;

    // strategy update reasons
    uint8 private constant STRATEGY_UPDATE_REASON_EDIT = 0;
    uint8 private constant STRATEGY_UPDATE_REASON_TRADE = 1;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 2000;
    uint32 private constant NEW_TRADING_FEE_PPM = 300_000;

    uint256 private constant FETCH_AMOUNT = 5;

    // mapping from token symbol to token
    mapping(string => Token) private symbolToToken;

    /**
     * @dev triggered when the network fee is updated
     */
    event TradingFeePPMUpdated(uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev triggered when a strategy is created
     */
    event StrategyCreated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

    /**
     * @dev triggered when a strategy is deleted
     */
    event StrategyDeleted(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

    /**
     * @dev triggered when a strategy is updated
     */
    event StrategyUpdated(
        uint256 indexed id,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1,
        uint8 reason
    );

    /**
     * @dev triggered when tokens are traded
     */
    event TokensTraded(
        address indexed trader,
        Token indexed sourceToken,
        Token indexed targetToken,
        uint256 sourceAmount,
        uint256 targetAmount,
        uint128 tradingFeeAmount,
        bool byTargetAmount
    );

    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev triggered when fees are withdrawn
     */
    event FeesWithdrawn(Token indexed token, address indexed recipient, uint256 indexed amount, address sender);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
        // Deploy Test Case Parser
        testCaseParser = new TestCaseParser();
        // Approve tokens to carbon controller
        vm.startPrank(admin);
        uint256 approveAmount = MAX_SOURCE_AMOUNT;
        token0.safeApprove(address(carbonController), approveAmount);
        token1.safeApprove(address(carbonController), approveAmount);
        token2.safeApprove(address(carbonController), approveAmount);
        vm.stopPrank();
        // Approve tokens to carbon controller
        vm.startPrank(user1);
        token0.safeApprove(address(carbonController), approveAmount);
        token1.safeApprove(address(carbonController), approveAmount);
        token2.safeApprove(address(carbonController), approveAmount);
        vm.stopPrank();
        // Set up symbol to token mappings
        symbolToToken["ETH"] = NATIVE_TOKEN;
        symbolToToken["TKN0"] = token0;
        symbolToToken["TKN1"] = token1;
        symbolToToken["TKN2"] = token2;
    }

    /**
     * @dev validation tests
     */

    /// @dev test that trading reverts when identical tokens are provided
    function testTradingRevertsWhenIdenticalTokensAreProvided(bool byTargetAmount) public {
        vm.startPrank(user1);
        vm.expectRevert(CarbonController.IdenticalAddresses.selector);
        simpleTrade(token0, token0, byTargetAmount, 1, -1);
        vm.stopPrank();
    }

    /// @dev test that trading reverts when the constraint is not valid
    function testTradingRevertsWhenTheConstraintIsNotValid(bool byTargetAmount) public {
        vm.startPrank(user1);
        vm.expectRevert(ZeroValue.selector);
        simpleTrade(token0, token1, byTargetAmount, 1, 0);
        vm.stopPrank();
    }

    /// @dev test that trading reverts when the contract is paused
    function testTradingRevertsWhenPaused(bool byTargetAmount) public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleEmergencyStopper(), user2);
        vm.stopPrank();
        vm.prank(user2);
        carbonController.pause();

        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        simpleTrade(token0, token1, byTargetAmount, 1, 1);
        vm.stopPrank();
    }

    /// @dev test that trading reverts if insufficient native token was sent
    function testTradingRevertsIfInsufficientNativeTokenWasSent(bool byTargetAmount) public {
        vm.startPrank(user1);

        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("ETH", "TKN0", byTargetAmount);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        TradeAction[] memory tradeActions = testCase.tradeActions;
        // trade
        if (byTargetAmount) {
            vm.expectRevert(CarbonController.InsufficientNativeTokenReceived.selector);
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, targetAmount, targetAmount / 2, -1);
        } else {
            vm.expectRevert(Strategies.NativeAmountMismatch.selector);
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, sourceAmount / 2, -1);
        }
        vm.stopPrank();
    }

    /// @dev test that trading reverts if unnecessary native token was sent
    function testTradingRevertsIfUnnecessaryNativeTokenWasSent(bool byTargetAmount) public {
        vm.startPrank(user1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("TKN0", "TKN1", byTargetAmount);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        TradeAction[] memory tradeActions = testCase.tradeActions;

        vm.expectRevert(CarbonController.UnnecessaryNativeTokenReceived.selector);
        if (byTargetAmount) {
            // expect trade between two tokens, but send ETH anyway
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, targetAmount, targetAmount, -1);
        } else {
            // expect trade between two tokens, but send ETH anyway
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, sourceAmount, -1);
        }
        vm.stopPrank();
    }

    /// @dev test that trading reverts if the deadline has expired
    function testTradingRevertsIfDeadlineHasExpired() public {
        vm.prank(user1);

        uint256 deadline = block.timestamp - 1;
        TradeAction[] memory tradeActions = new TradeAction[](0);
        vm.expectRevert(CarbonController.DeadlineExpired.selector);
        carbonController.tradeBySourceAmount(token0, token1, tradeActions, deadline, 1);
    }

    /// @dev test that trading reverts if trade actions are provided with strategy ids which don't match the source or target tokens
    function testTradingRevertsIfTradeActionsAreProvidedWithStrategyIdsNotMatchingTheSourceOrTargetTokens(
        bool byTargetAmount
    ) public {
        vm.startPrank(user1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("ETH", "TKN1", byTargetAmount);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        // get second test case data
        TestCaseParser.TestCase memory testCase2 = testCaseParser.getTestCase("TKN0", "TKN1", byTargetAmount);

        // create more strategies
        createStrategies(testCase2);

        // edit one of the actions to use the extra strategy created
        tradeActions[2].strategyId = generateStrategyId(2, testCase.strategies.length + 1);

        vm.expectRevert(Strategies.InvalidTradeActionStrategyId.selector);

        if (byTargetAmount) {
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, targetAmount, targetAmount, -1);
        } else {
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, sourceAmount, -1);
        }

        vm.stopPrank();
    }

    /// @dev test that trading reverts if attempting to trade on a strategy which does not exist
    function testTradingRevertsIfAttemptingToTradeOnAStrategyWhichDoesNotExist(bool byTargetAmount) public {
        vm.startPrank(user1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("ETH", "TKN0", byTargetAmount);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        // edit one of the actions to use a strategy that does not exist
        tradeActions[2].strategyId = generateStrategyId(1, 1000);

        vm.expectRevert(Strategies.OrderDisabled.selector);

        if (byTargetAmount) {
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, targetAmount, targetAmount, -1);
        } else {
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, sourceAmount, -1);
        }

        vm.stopPrank();
    }

    /// @dev test that trading reverts if attempting to trade on a non existing strategy
    function testTradingRevertsIfAttemptingToTradeOnANonExistingStrategy(bool byTargetAmount) public {
        vm.startPrank(user1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("ETH", "TKN0", byTargetAmount);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // edit one of the target orders and disable it by setting all rates to 0
        testCase.strategies[1].orders[1].y = 0;
        testCase.strategies[1].orders[1].z = 0;
        testCase.strategies[1].orders[1].A = 0;
        testCase.strategies[1].orders[1].B = 0;
        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        vm.expectRevert(Strategies.OrderDisabled.selector);

        if (byTargetAmount) {
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, targetAmount, targetAmount, -1);
        } else {
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, sourceAmount, -1);
        }

        vm.stopPrank();
    }

    /// @dev test that trading reverts when one of or both token addresses are zero
    function testTradingRevertsWhenOneOfOrBothAddressesAreZero(uint256 i0, uint256 i1, bool byTargetAmount) public {
        vm.startPrank(user1);

        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, Token.wrap(address(0)), Token.wrap(address(0))];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        uint256 amount = 1000;

        TradeAction[] memory tradeActions = new TradeAction[](0);

        vm.expectRevert(InvalidAddress.selector);
        simpleTrade(tokens[i0], tokens[i1], byTargetAmount, tradeActions, amount, amount, -1);

        vm.stopPrank();
    }

    /// @dev test that trading reverts when min return or max input constraint is unmet
    function testTradingRevertsWhenMinReturnOrMaxInputIsUnmet(bool byTargetAmount) public {
        vm.startPrank(user1);

        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("TKN0", "TKN1", byTargetAmount);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        TradeAction[] memory tradeActions = testCase.tradeActions;
        // trade
        if (byTargetAmount) {
            vm.expectRevert(Strategies.GreaterThanMaxInput.selector);
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, targetAmount, 0, 1);
        } else {
            vm.expectRevert(Strategies.LowerThanMinReturn.selector);
            simpleTrade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, 0, type(int256).max);
        }
        vm.stopPrank();
    }

    /// @dev test that trading reverts if the transaction's value is lower than the max input constraint
    function testTradingRevertsIfTransactionsValueIsLowerThanMaxInputConstraint() public {
        vm.prank(user1);
        // trade
        TradeAction[] memory tradeActions = new TradeAction[](0);
        vm.expectRevert(CarbonController.UnnecessaryNativeTokenReceived.selector);
        simpleTrade(token0, token1, true, tradeActions, 1, 500, 1000);
    }

    /// @dev test that trading fees collected are stored and returned correctly
    function testTradingFeesCollectedAreStoredAndReturnedCorrectly(uint256 i0, uint256 i1, bool byTargetAmount) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        // trade
        trade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, -1, false);

        uint256 sourceTokenFees = carbonController.accumulatedFees(tokens[0]);
        uint256 targetTokenFees = carbonController.accumulatedFees(tokens[1]);
        uint256 tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);

        if (byTargetAmount) {
            assertEq(sourceTokenFees, tradingFeeAmount);
            assertEq(targetTokenFees, 0);
        } else {
            assertEq(sourceTokenFees, 0);
            assertEq(targetTokenFees, tradingFeeAmount);
        }

        vm.stopPrank();
    }

    /// @dev test that overriden trading fees for pairs collected are stored and returned correctly
    function testOverridenTradingFeesCollectedAreStoredAndReturnedCorrectly(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount,
        uint32 customFee
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);
        // bound custom pair fee
        customFee = uint32(bound(customFee, 1, 100_000));

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        // get token pair
        Pair memory pair = carbonController.pair(tokens[0], tokens[1]);

        vm.stopPrank();

        vm.prank(admin);
        // set custom trading fee for the token pair
        carbonController.setTradingFeePPMOverrides(pair.id, customFee);

        vm.startPrank(user1);

        // trade
        trade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, -1, false);

        uint256 sourceTokenFees = carbonController.accumulatedFees(tokens[0]);
        uint256 targetTokenFees = carbonController.accumulatedFees(tokens[1]);
        uint256 tradingFeeAmount = getTradingFeeAmount(pair.id, byTargetAmount, sourceAmount, targetAmount);

        if (byTargetAmount) {
            assertEq(sourceTokenFees, tradingFeeAmount);
            assertEq(targetTokenFees, 0);
        } else {
            assertEq(sourceTokenFees, 0);
            assertEq(targetTokenFees, tradingFeeAmount);
        }

        vm.stopPrank();
    }

    /// @dev test that trading with fees set to zero is allowed
    function testAllowsTradingWithFeesSetToZero(uint256 i0, uint256 i1, bool byTargetAmount) public {
        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        vm.prank(admin);
        carbonController.setTradingFeePPM(0);

        vm.startPrank(user1);

        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        // expect to emit event with correct args
        vm.expectEmit();
        emit TokensTraded(user1, tokens[0], tokens[1], sourceAmount, targetAmount, uint128(0), byTargetAmount);
        trade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, -1, false);

        uint256 sourceTokenFees = carbonController.accumulatedFees(tokens[0]);
        uint256 targetTokenFees = carbonController.accumulatedFees(tokens[1]);

        assertEq(sourceTokenFees, 0);
        assertEq(targetTokenFees, 0);

        vm.stopPrank();
    }

    /// @dev test that trading with fee on transfer tokens is allowed
    function testAllowsTradingWithFeeOnTransferTokens(bool byTargetAmount) public {
        vm.startPrank(user1);

        // create test order
        Order memory order = generateTestOrder();

        uint256 sourceAmount = 800000000;

        // approve fee on transfer token
        feeOnTransferToken.safeApprove(address(carbonController), sourceAmount * 2);

        // disable fee to create strategy
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeEnabled(false);

        // create strategy
        uint256 strategyId = carbonController.createStrategy(feeOnTransferToken, token1, [order, order]);

        // enable fee to test trading
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeEnabled(true);

        // set the trade actions to act on the fee on transfer token strategy
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = TradeAction({ strategyId: strategyId, amount: byTargetAmount ? 1 : uint128(sourceAmount) });

        vm.stopPrank();

        // set trading fee to 0
        vm.prank(admin);
        carbonController.setTradingFeePPM(0);

        vm.prank(user1);
        simpleTrade(feeOnTransferToken, token1, byTargetAmount, tradeActions, sourceAmount, 0, -1);
    }

    /// @dev test that trading emits a strategy updated event for every trade action
    function testTradingEmitsStrategyUpdatedEventForEveryTradeAction(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;

        // create test case strategies
        createStrategies(testCase);
        // set the trade actions to be from the first test case
        TradeAction[] memory tradeActions = testCase.tradeActions;

        // expect to emit the events with correct args in the correct order
        for (uint256 i = 0; i < testCase.strategies.length; ++i) {
            vm.expectEmit();
            emit StrategyUpdated(
                tradeActions[i].strategyId,
                tokens[0],
                tokens[1],
                testCase.strategies[i].expectedOrders[0],
                testCase.strategies[i].expectedOrders[1],
                1
            );
        }
        trade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, -1, false);

        vm.stopPrank();
    }

    /// @dev test that trading emits the tokens traded event on a successful trade
    function testTradingEmitsTokensTradedEvent(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount,
        bool overrideTradingFee
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];

        // create test case strategies
        createStrategies(testCase);

        Pair memory pair = carbonController.pair(tokens[0], tokens[1]);
        if (overrideTradingFee) {
            vm.stopPrank();
            vm.prank(admin);
            carbonController.setTradingFeePPMOverrides(pair.id, NEW_TRADING_FEE_PPM);
            vm.startPrank(user1);
        }
        // get trading fee amount
        uint128 tradingFeeAmount = uint128(
            getTradingFeeAmount(pair.id, byTargetAmount, testCase.sourceAmount, testCase.targetAmount)
        );
        // get expected source and target amounts
        (uint256 expectedSourceAmount, uint256 expectedTargetAmount) = getExpectedSourceTargetAmounts(
            byTargetAmount,
            testCase.sourceAmount,
            testCase.targetAmount,
            tradingFeeAmount
        );

        // expect to emit event with correct args
        vm.expectEmit();
        emit TokensTraded(
            user1,
            tokens[0],
            tokens[1],
            expectedSourceAmount,
            expectedTargetAmount,
            tradingFeeAmount,
            byTargetAmount
        );
        trade(tokens[0], tokens[1], byTargetAmount, testCase.tradeActions, testCase.sourceAmount, -1, false);

        vm.stopPrank();
    }

    /// @dev test that trading stores orders correctly
    function testOrdersAreStoredCorrectly(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount,
        bool equalHighestAndMarginalRate,
        bool inverseOrders
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount,
            equalHighestAndMarginalRate,
            inverseOrders
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;

        // create test case strategies
        createStrategies(testCase, inverseOrders);

        // trade
        trade(tokens[0], tokens[1], byTargetAmount, testCase.tradeActions, sourceAmount, -1, false);

        // get stored strategies
        Strategy[] memory strategies = carbonController.strategiesByPair(tokens[0], tokens[1], 0, 0);

        // assert stored order values are correct
        for (uint256 i = 0; i < strategies.length; ++i) {
            assertTrue(compareOrders(strategies[i].orders[0], testCase.strategies[i].expectedOrders[0]));
            assertTrue(compareOrders(strategies[i].orders[1], testCase.strategies[i].expectedOrders[1]));
        }

        vm.stopPrank();
    }

    /// @dev test that irrelevant strategies remain unchanged after a trade
    function testIrrelevantStrategiesRemainUnchangedAfterATrade(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount,
        bool equalHighestAndMarginalRate,
        bool inverseOrders
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount,
            equalHighestAndMarginalRate,
            inverseOrders
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;

        // create test case strategies
        createStrategies(testCase, inverseOrders);

        // save current state for later assertion
        Strategy[] memory originalStrategies = carbonController.strategiesByPair(tokens[0], tokens[1], 0, 0);

        // trade only on the first trade action
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = testCase.tradeActions[0];
        trade(tokens[0], tokens[1], byTargetAmount, tradeActions, sourceAmount, -1, false);

        // get stored strategies after trade
        Strategy[] memory updatedStrategies = carbonController.strategiesByPair(tokens[0], tokens[1], 0, 0);

        // assert stored order values are correct

        // first strategy should be updated
        assertTrue(compareOrders(updatedStrategies[0].orders[0], testCase.strategies[0].expectedOrders[0]));
        assertTrue(compareOrders(updatedStrategies[0].orders[1], testCase.strategies[0].expectedOrders[1]));

        // all other strategies should be the same as before the trade
        for (uint256 i = 1; i < updatedStrategies.length; ++i) {
            assertTrue(compareOrders(updatedStrategies[i].orders[0], originalStrategies[i].orders[0]));
            assertTrue(compareOrders(updatedStrategies[i].orders[1], originalStrategies[i].orders[1]));
        }

        vm.stopPrank();
    }

    /// @dev test that trading updates balances correctly
    function testTradingUpdatesBalancesCorrectly(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount,
        bool inverseOrders,
        bool overrideTradingFee
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount,
            inverseOrders
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase, inverseOrders);

        Pair memory pair = carbonController.pair(tokens[0], tokens[1]);
        if (overrideTradingFee) {
            vm.stopPrank();
            vm.prank(admin);
            carbonController.setTradingFeePPMOverrides(pair.id, NEW_TRADING_FEE_PPM);
            vm.startPrank(user1);
        }
        // get trading fee amount
        uint128 tradingFeeAmount = uint128(
            getTradingFeeAmount(pair.id, byTargetAmount, testCase.sourceAmount, testCase.targetAmount)
        );

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[0].balanceOf(user1),
            tokens[1].balanceOf(user1),
            tokens[0].balanceOf(address(carbonController)),
            tokens[1].balanceOf(address(carbonController))
        ];

        // trade
        trade(tokens[0], tokens[1], byTargetAmount, testCase.tradeActions, sourceAmount, -1, false);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[0].balanceOf(user1),
            tokens[1].balanceOf(user1),
            tokens[0].balanceOf(address(carbonController)),
            tokens[1].balanceOf(address(carbonController))
        ];

        // get expected source and target amounts
        (uint256 expectedSourceAmount, uint256 expectedTargetAmount) = getExpectedSourceTargetAmounts(
            byTargetAmount,
            sourceAmount,
            targetAmount,
            tradingFeeAmount
        );

        // assert balances are correct
        // user1 balance should decrease by y amount
        assertEq(balancesAfter[0], balancesBefore[0] - expectedSourceAmount);
        assertEq(balancesAfter[1], balancesBefore[1] + expectedTargetAmount);

        // controller balance should increase by y amount
        assertEq(balancesAfter[2], balancesBefore[2] + expectedSourceAmount);
        assertEq(balancesAfter[3], balancesBefore[3] - expectedTargetAmount);

        vm.stopPrank();
    }

    /// @dev test that excess native token sent in a trade is refunded
    function testExcessNativeTokenIsRefunded(uint256 i0, uint256 i1, bool byTargetAmount, bool inverseOrders) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount,
            inverseOrders
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // create test case strategies
        createStrategies(testCase, inverseOrders);
        // get trading fee amount
        uint128 tradingFeeAmount = uint128(getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount));

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[0].balanceOf(user1),
            tokens[1].balanceOf(user1),
            tokens[0].balanceOf(address(carbonController)),
            tokens[1].balanceOf(address(carbonController))
        ];

        // trade
        trade(tokens[0], tokens[1], byTargetAmount, testCase.tradeActions, sourceAmount, -1, true);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[0].balanceOf(user1),
            tokens[1].balanceOf(user1),
            tokens[0].balanceOf(address(carbonController)),
            tokens[1].balanceOf(address(carbonController))
        ];

        // get expected source and target amounts
        (uint256 expectedSourceAmount, uint256 expectedTargetAmount) = getExpectedSourceTargetAmounts(
            byTargetAmount,
            sourceAmount,
            targetAmount,
            tradingFeeAmount
        );

        // assert balances are correct
        // user1 balance should decrease by y amount
        assertEq(balancesAfter[0], balancesBefore[0] - expectedSourceAmount);
        assertEq(balancesAfter[1], balancesBefore[1] + expectedTargetAmount);

        // controller balance should increase by y amount
        assertEq(balancesAfter[2], balancesBefore[2] + expectedSourceAmount);
        assertEq(balancesAfter[3], balancesBefore[3] - expectedTargetAmount);

        vm.stopPrank();
    }

    /// @dev test that trading functions return correct amounts
    function testTradingFunctionReturnsAmounts(uint256 i0, uint256 i1, bool byTargetAmount) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // get trading fee amount
        uint128 tradingFeeAmount = uint128(getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount));
        // get expected source and target amounts
        (uint256 expectedSourceAmount, uint256 expectedTargetAmount) = getExpectedSourceTargetAmounts(
            byTargetAmount,
            sourceAmount,
            targetAmount,
            tradingFeeAmount
        );

        // create test case strategies
        createStrategies(testCase);

        // trade and get returned amount
        uint128 tradeAmount = trade(
            tokens[0],
            tokens[1],
            byTargetAmount,
            testCase.tradeActions,
            sourceAmount,
            -1,
            false
        );

        if (byTargetAmount) {
            assertEq(uint128(expectedSourceAmount), tradeAmount);
        } else {
            assertEq(uint128(expectedTargetAmount), tradeAmount);
        }

        vm.stopPrank();
    }

    /// @dev test that trading amount estimation functions return correct amounts
    function testTradingAmountFunctionsReturnAmounts(uint256 i0, uint256 i1, bool byTargetAmount) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // get trading fee amount
        uint128 tradingFeeAmount = uint128(getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount));
        // get expected source and target amounts
        (uint256 expectedSourceAmount, uint256 expectedTargetAmount) = getExpectedSourceTargetAmounts(
            byTargetAmount,
            sourceAmount,
            targetAmount,
            tradingFeeAmount
        );

        // create test case strategies
        createStrategies(testCase);

        // calculate trade amount
        uint128 tradeAmount;
        if (byTargetAmount) {
            tradeAmount = carbonController.calculateTradeSourceAmount(tokens[0], tokens[1], testCase.tradeActions);
        } else {
            tradeAmount = carbonController.calculateTradeTargetAmount(tokens[0], tokens[1], testCase.tradeActions);
        }

        // assert amounts are correct
        if (byTargetAmount) {
            assertEq(uint128(expectedSourceAmount), tradeAmount);
        } else {
            assertEq(uint128(expectedTargetAmount), tradeAmount);
        }

        vm.stopPrank();
    }

    /// @dev test that trading amount estimation functions return correct amounts for inverted orders
    function testTradingAmountFunctionsReturnAmountsForInvertedOrders(
        uint256 i0,
        uint256 i1,
        bool byTargetAmount
    ) public {
        vm.startPrank(user1);

        // use two of the below 3 token symbols for the strategy
        string[3] memory tokenSymbols = ["TKN0", "TKN1", "ETH"];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(
            tokenSymbols[i0],
            tokenSymbols[i1],
            byTargetAmount,
            false,
            true
        );
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        uint256 sourceAmount = testCase.sourceAmount;
        uint256 targetAmount = testCase.targetAmount;

        // get trading fee amount
        uint128 tradingFeeAmount = uint128(getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount));
        // get expected source and target amounts
        (uint256 expectedSourceAmount, uint256 expectedTargetAmount) = getExpectedSourceTargetAmounts(
            byTargetAmount,
            sourceAmount,
            targetAmount,
            tradingFeeAmount
        );

        // create test case strategies
        createStrategies(testCase, true);

        // calculate trade amount
        uint128 tradeAmount;
        if (byTargetAmount) {
            tradeAmount = carbonController.calculateTradeSourceAmount(tokens[0], tokens[1], testCase.tradeActions);
        } else {
            tradeAmount = carbonController.calculateTradeTargetAmount(tokens[0], tokens[1], testCase.tradeActions);
        }

        // assert amounts are correct
        if (byTargetAmount) {
            assertEq(uint128(expectedSourceAmount), tradeAmount);
        } else {
            assertEq(uint128(expectedTargetAmount), tradeAmount);
        }

        vm.stopPrank();
    }

    /// @dev test that trading reverts if tradeActions in trading amount functions are provided with strategyIds not matching the source/target tokens
    function testRevertsIfTradeActionsInTradingAmountFunctionsAreProvidedWithIncorrectStrategyIds(
        bool byTargetAmount
    ) public {
        vm.startPrank(user1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("ETH", "TKN0", byTargetAmount);

        // get test case data for different tokens
        TestCaseParser.TestCase memory testCase2 = testCaseParser.getTestCase("TKN0", "TKN1", byTargetAmount);

        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];

        // create test case strategies
        createStrategies(testCase);
        // create different tokens test case data
        createStrategies(testCase2);

        // edit one of the trade actions to use the extra strategy created
        testCase.tradeActions[2].strategyId = generateStrategyId(2, testCase.strategies.length + 1);

        // expect a revert
        vm.expectRevert(Strategies.InvalidTradeActionStrategyId.selector);
        if (byTargetAmount) {
            carbonController.calculateTradeSourceAmount(tokens[0], tokens[1], testCase.tradeActions);
        } else {
            carbonController.calculateTradeTargetAmount(tokens[0], tokens[1], testCase.tradeActions);
        }

        vm.stopPrank();
    }

    /// @dev test that trading reverts if orders have insufficient liquidity to execute the requested trade
    function testTradingRevertsIfOrdersHaveInsufficientLiquidityToExecuteTheRequestedTrade(bool byTargetAmount) public {
        vm.startPrank(user1);

        // get test case data
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase("TKN0", "TKN1", byTargetAmount);

        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];

        // create test case strategies
        createStrategies(testCase);

        // get the strategy of the first trade action
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = testCase.tradeActions[0];
        Strategy memory strategy = carbonController.strategy(tradeActions[0].strategyId);

        // get the target order
        Order memory order = strategy.tokens[0] == tokens[1] ? strategy.orders[0] : strategy.orders[1];

        // increase the input amount so that the target amount is higher than the total liquidity
        // and calculate the new source amount
        uint128 sourceAmount;
        if (byTargetAmount) {
            tradeActions[0].amount = uint128(order.y) + 1e18;
            sourceAmount = carbonController.calculateTradeSourceAmount(tokens[0], tokens[1], tradeActions);
        } else {
            tradeActions[0].amount = uint128(order.y);
            sourceAmount = carbonController.calculateTradeSourceAmount(tokens[0], tokens[1], tradeActions);
            sourceAmount = sourceAmount + 1e18;
            tradeActions[0].amount = sourceAmount;
        }

        // expect a revert
        vm.expectRevert(Strategies.InsufficientLiquidity.selector);
        simpleTrade(tokens[0], tokens[1], false, tradeActions, sourceAmount, 0, -1);

        vm.stopPrank();
    }

    /// @dev helper function to create multiple strategies based on a test case
    function createStrategies(TestCaseParser.TestCase memory testCase) private returns (Strategy[] memory strategies) {
        TestCaseParser.TestStrategy[] memory testStrategies = testCase.strategies;
        // initialize strategies array
        strategies = new Strategy[](testStrategies.length);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        for (uint256 i = 0; i < testStrategies.length; ++i) {
            Order[2] memory orders = testCase.strategies[i].orders;
            uint256 val = tokens[0] == NATIVE_TOKEN ? orders[0].y : 0;
            val += tokens[1] == NATIVE_TOKEN ? orders[1].y : 0;
            uint256 strategyId = carbonController.createStrategy{ value: val }(tokens[0], tokens[1], orders);
            strategies[i] = carbonController.strategy(strategyId);
        }
    }

    /// @dev helper function to create multiple strategies based on a test case, overriden with inverse orders boolean
    function createStrategies(
        TestCaseParser.TestCase memory testCase,
        bool inverseOrders
    ) private returns (Strategy[] memory strategies) {
        TestCaseParser.TestStrategy[] memory testStrategies = testCase.strategies;
        // initialize strategies array
        strategies = new Strategy[](testStrategies.length);
        Token[2] memory tokens = [symbolToToken[testCase.sourceSymbol], symbolToToken[testCase.targetSymbol]];
        for (uint256 i = 0; i < testStrategies.length; ++i) {
            Order[2] memory orders = testCase.strategies[i].orders;
            uint256 val;
            uint256 strategyId;
            // strategy tokens are also inversed if the orders are
            if (inverseOrders && i % 2 == 0) {
                val = tokens[1] == NATIVE_TOKEN ? orders[0].y : 0;
                val += tokens[0] == NATIVE_TOKEN ? orders[1].y : 0;
                strategyId = carbonController.createStrategy{ value: val }(tokens[1], tokens[0], orders);
            } else {
                val = tokens[0] == NATIVE_TOKEN ? orders[0].y : 0;
                val += tokens[1] == NATIVE_TOKEN ? orders[1].y : 0;
                strategyId = carbonController.createStrategy{ value: val }(tokens[0], tokens[1], orders);
            }
            strategies[i] = carbonController.strategy(strategyId);
        }
    }

    /// @dev helper function to make a trade
    function simpleTrade(
        Token sourceToken,
        Token targetToken,
        bool byTargetAmount,
        uint256 sourceAmount,
        int256 constraint
    ) private {
        uint256 deadline = block.timestamp + 1000;
        TradeAction[] memory tradeActions = new TradeAction[](0);
        if (byTargetAmount) {
            uint128 maxInput = setConstraint(constraint, byTargetAmount, sourceAmount);
            carbonController.tradeByTargetAmount(sourceToken, targetToken, tradeActions, deadline, maxInput);
        } else {
            uint128 minReturn = setConstraint(constraint, byTargetAmount, sourceAmount);
            carbonController.tradeBySourceAmount(sourceToken, targetToken, tradeActions, deadline, minReturn);
        }
    }

    /// @dev helper function to make a trade with trade actions
    function simpleTrade(
        Token sourceToken,
        Token targetToken,
        bool byTargetAmount,
        TradeAction[] memory tradeActions,
        uint256 sourceAmount,
        uint256 txValue,
        int256 constraint
    ) private {
        uint256 deadline = block.timestamp + 1000;
        if (byTargetAmount) {
            uint128 maxInput = setConstraint(constraint, byTargetAmount, sourceAmount);
            carbonController.tradeByTargetAmount{ value: txValue }(
                sourceToken,
                targetToken,
                tradeActions,
                deadline,
                maxInput
            );
        } else {
            uint128 minReturn = setConstraint(constraint, byTargetAmount, sourceAmount);
            carbonController.tradeBySourceAmount{ value: txValue }(
                sourceToken,
                targetToken,
                tradeActions,
                deadline,
                minReturn
            );
        }
    }

    /// @dev helper function to make a trade with trade actions
    function trade(
        Token sourceToken,
        Token targetToken,
        bool byTargetAmount,
        TradeAction[] memory tradeActions,
        uint256 sourceAmount,
        int256 constraint,
        bool sendExcessNativeToken
    ) private returns (uint128) {
        uint256 deadline = block.timestamp + 1000;
        Pair memory pair = carbonController.pair(sourceToken, targetToken);
        if (byTargetAmount) {
            sourceAmount = _addFee(sourceAmount, pair.id);
            uint128 maxInput = setConstraint(constraint, byTargetAmount, sourceAmount);
            uint256 txValue = sourceToken == NATIVE_TOKEN ? sourceAmount : 0;
            txValue = sendExcessNativeToken ? txValue * 2 : txValue;
            return
                carbonController.tradeByTargetAmount{ value: txValue }(
                    sourceToken,
                    targetToken,
                    tradeActions,
                    deadline,
                    maxInput
                );
        } else {
            uint128 minReturn = setConstraint(constraint, byTargetAmount, sourceAmount);
            uint256 txValue = sourceToken == NATIVE_TOKEN ? sourceAmount : 0;
            txValue = sendExcessNativeToken ? txValue * 2 : txValue;
            return
                carbonController.tradeBySourceAmount{ value: txValue }(
                    sourceToken,
                    targetToken,
                    tradeActions,
                    deadline,
                    minReturn
                );
        }
    }

    /// @dev returns the expected source and target amounts for a trade including fees
    function getExpectedSourceTargetAmounts(
        bool byTargetAmount,
        uint256 sourceAmount,
        uint256 targetAmount,
        uint256 tradingFeeAmount
    ) private pure returns (uint256 expectedSourceAmount, uint256 expectedTargetAmount) {
        if (byTargetAmount) {
            expectedSourceAmount = sourceAmount + tradingFeeAmount;
            expectedTargetAmount = targetAmount;
        } else {
            expectedSourceAmount = sourceAmount;
            expectedTargetAmount = targetAmount - tradingFeeAmount;
        }
    }

    /// @dev helper function to return the trading fee amount
    function getTradingFeeAmount(
        bool byTargetAmount,
        uint256 sourceAmount,
        uint256 targetAmount
    ) private view returns (uint256) {
        uint32 tradingFeePPM = carbonController.tradingFeePPM();
        if (byTargetAmount) {
            uint128 fee = uint128(MathEx.mulDivC(sourceAmount, PPM_RESOLUTION, PPM_RESOLUTION - tradingFeePPM));
            return uint256(fee - sourceAmount);
        } else {
            int256 fee = int256(uint256(MathEx.mulDivF(targetAmount, PPM_RESOLUTION - tradingFeePPM, PPM_RESOLUTION)));
            int256 targetAmountWithFee = fee - int256(targetAmount);
            return uint256(targetAmountWithFee * (-1));
        }
    }

    /// @dev helper function to return the overriden trading fee amount for a given pair (if not set, returns the trading fee)
    function getTradingFeeAmount(
        uint128 pairId,
        bool byTargetAmount,
        uint256 sourceAmount,
        uint256 targetAmount
    ) private view returns (uint256) {
        // override protocol-wide trading fee with custom one if it's set for the pair
        uint32 tradingFeePPM = carbonController.tradingFeePPM();
        uint32 tradingFeePPMOverrides = carbonController.tradingFeePPMOverrides(pairId);
        tradingFeePPM = tradingFeePPMOverrides == 0 ? tradingFeePPM : tradingFeePPMOverrides;
        if (byTargetAmount) {
            uint128 fee = uint128(MathEx.mulDivC(sourceAmount, PPM_RESOLUTION, PPM_RESOLUTION - tradingFeePPM));
            return uint256(fee - sourceAmount);
        } else {
            int256 fee = int256(uint256(MathEx.mulDivF(targetAmount, PPM_RESOLUTION - tradingFeePPM, PPM_RESOLUTION)));
            int256 targetAmountWithFee = fee - int256(targetAmount);
            return uint256(targetAmountWithFee * (-1));
        }
    }

    /**
     * @dev calculates the required amount plus fee
     */
    function _addFee(uint256 amount, uint128 pairId) private view returns (uint256) {
        // override protocol-wide trading fee with custom one if it's set for the pair
        uint32 tradingFeePPM = carbonController.tradingFeePPM();
        uint32 tradingFeePPMOverrides = carbonController.tradingFeePPMOverrides(pairId);
        tradingFeePPM = tradingFeePPMOverrides == 0 ? tradingFeePPM : tradingFeePPMOverrides;
        // divide the input amount by `1 - fee`
        return uint256(MathEx.mulDivC(amount, PPM_RESOLUTION, PPM_RESOLUTION - tradingFeePPM));
    }

    /// @dev helper function to set constraint for trading function (maxInput or minReturn)
    function setConstraint(
        int256 constraint,
        bool byTargetAmount,
        uint256 expectedResultAmount
    ) private pure returns (uint128) {
        // expectedResultAmount should be less than uint128
        assert(expectedResultAmount <= type(uint128).max);
        if (constraint < 0) {
            return byTargetAmount ? uint128(expectedResultAmount) : uint128(1);
        } else {
            return uint128(uint256(constraint));
        }
    }

    /// @dev helper function to compare order structs
    function compareOrders(Order memory order1, Order memory order2) private pure returns (bool) {
        if (order1.y != order2.y || order1.z != order2.z || order1.A != order2.A || order1.B != order2.B) {
            return false;
        }
        return true;
    }

    /// @dev helper function to generate test order with custom y amount
    function generateTestOrder(uint256 amount) private pure returns (Order memory order) {
        // amount should be less than uint128
        assert(amount <= type(uint128).max);
        return Order({ y: uint128(amount), z: 8000000, A: 736899889, B: 12148001999 });
    }

    /// @dev helper function to generate test order
    function generateTestOrder() private pure returns (Order memory order) {
        return Order({ y: 800000, z: 8000000, A: 736899889, B: 12148001999 });
    }

    /// @dev helper function to generate a disabled order (with all zeroed values)
    function generateDisabledOrder() private pure returns (Order memory order) {
        return Order({ y: 0, z: 0, A: 0, B: 0 });
    }

    function generateStrategyId(uint256 pairId, uint256 strategyIndex) private pure returns (uint256) {
        return (pairId << 128) | strategyIndex;
    }

    function abs(int64 val) private pure returns (uint64) {
        return val < 0 ? uint64(-val) : uint64(val);
    }
}
