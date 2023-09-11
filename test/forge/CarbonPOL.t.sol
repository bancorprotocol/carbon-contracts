// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { CarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

import { AccessDenied, InvalidAddress, InvalidFee, ZeroValue } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";
import { MathEx } from "../../contracts/utility/MathEx.sol";
import { ExpDecayMath } from "../../contracts/utility/ExpDecayMath.sol";
import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

import { ICarbonPOL } from "../../contracts/pol/interfaces/ICarbonPOL.sol";

contract CarbonPOLTest is TestFixture {
    using Address for address payable;

    uint32 private constant MARKET_PRICE_MULTIPLY_DEFAULT = 2;
    uint32 private constant MARKET_PRICE_MULTIPLY_UPDATED = 3;

    uint32 private constant PRICE_DECAY_HALFLIFE_DEFAULT = 10 days;
    uint32 private constant PRICE_DECAY_HALFLIFE_UPDATED = 15 days;

    // Events

    /**
     * @notice triggered when trading is enabled for a token
     */
    event TradingEnabled(Token indexed token, ICarbonPOL.Price price);

    /**
     * @notice triggered after a successful trade is executed
     */
    event TokenTraded(address indexed caller, Token indexed token, uint128 amount, uint128 ethReceived);

    /**
     * @notice triggered when the market price multiplier is updated
     */
    event MarketPriceMultiplyUpdated(uint32 prevMarketPriceMultiply, uint32 newMarketPriceMultiply);

    /**
     * @notice triggered when the price decay halflife is updated
     */
    event PriceDecayHalfLifeUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

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
        // Deploy Carbon POL
        deployCarbonPOL();
        // Transfer tokens to Carbon POL
        transferTokensToCarbonPOL();
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
     * @dev market price multiply tests
     */

    /// @dev test that setMarketPriceMultiply should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheMarketPriceMultiply() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.setMarketPriceMultiply(MARKET_PRICE_MULTIPLY_UPDATED);
    }

    /// @dev test that setMarketPriceMultiply should revert when a setting to an invalid value
    function testShouldRevertSettingTheMarketPriceMultiplyWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonPOL.setMarketPriceMultiply(0);
    }

    /// @dev test that setMarketPriceMultiply with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameMarketPriceMultiply() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit MarketPriceMultiplyUpdated(MARKET_PRICE_MULTIPLY_DEFAULT, MARKET_PRICE_MULTIPLY_DEFAULT);
        carbonPOL.setMarketPriceMultiply(MARKET_PRICE_MULTIPLY_DEFAULT);
    }

    /// @dev test that admin should be able to update the market price multiply
    function testShouldBeAbleToSetAndUpdateTheMarketPriceMultiply() public {
        vm.startPrank(admin);
        uint32 marketPriceMultiply = carbonPOL.marketPriceMultiply();
        assertEq(marketPriceMultiply, MARKET_PRICE_MULTIPLY_DEFAULT);

        vm.expectEmit();
        emit MarketPriceMultiplyUpdated(MARKET_PRICE_MULTIPLY_DEFAULT, MARKET_PRICE_MULTIPLY_UPDATED);
        carbonPOL.setMarketPriceMultiply(MARKET_PRICE_MULTIPLY_UPDATED);

        marketPriceMultiply = carbonPOL.marketPriceMultiply();
        assertEq(marketPriceMultiply, MARKET_PRICE_MULTIPLY_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev price decay half-life tests
     */

    /// @dev test that setPriceDecayHalfLife should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetThePriceDecayHalfLife() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_UPDATED);
    }

    /// @dev test that setPriceDecayHalfLife should revert when a setting to an invalid value
    function testShouldRevertSettingTheRewardsPPMWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonPOL.setPriceDecayHalfLife(0);
    }

    /// @dev test that setPriceDecayHalfLife with the same value should be ignored
    function testFailShouldIgnoreSettingTheSamePriceDecayHalfLife() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit PriceDecayHalfLifeUpdated(PRICE_DECAY_HALFLIFE_DEFAULT, PRICE_DECAY_HALFLIFE_DEFAULT);
        carbonPOL.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_DEFAULT);
    }

    /// @dev test that admin should be able to update the price decay half-life
    function testShouldBeAbleToSetAndUpdateThePriceDecayHalfLife() public {
        vm.startPrank(admin);
        uint32 priceDecayHalfLife = carbonPOL.priceDecayHalfLife();
        assertEq(priceDecayHalfLife, PRICE_DECAY_HALFLIFE_DEFAULT);

        vm.expectEmit();
        emit PriceDecayHalfLifeUpdated(PRICE_DECAY_HALFLIFE_DEFAULT, PRICE_DECAY_HALFLIFE_UPDATED);
        carbonPOL.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_UPDATED);

        priceDecayHalfLife = carbonPOL.priceDecayHalfLife();
        assertEq(priceDecayHalfLife, PRICE_DECAY_HALFLIFE_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev trading tests
     */

    /// @dev test trading should be disabled initially for all tokens
    function testTradingShouldBeDisabledInitially(uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // assert trading is disabled
        assertFalse(carbonPOL.tradingEnabled(tokens[i]));
    }

    /// @dev test non admin shouldn't be able to enable trading for token
    function testNonAdminShouldntBeAbleToEnableTradingForToken(uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // enable trading
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.enableTrading(tokens[i], ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 }));
    }

    /// @dev test admin should be able to enable trading for token
    function testAdminShouldBeAbleToEnableTradingForToken(uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // enable trading
        vm.prank(admin);
        carbonPOL.enableTrading(tokens[i], ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 }));
        // assert trading is enabled
        assertTrue(carbonPOL.tradingEnabled(tokens[i]));
    }

    /// @dev test enabling trading for a token should emit an event
    function testEnablingTradingForTokenShouldEmitAnEvent(uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        ICarbonPOL.Price memory price = ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 });
        vm.prank(admin);
        // expect event to be emitted
        vm.expectEmit();
        emit TradingEnabled(tokens[i], price);
        // enable trading
        carbonPOL.enableTrading(tokens[i], price);
    }

    /// @dev test should revert when setting invalid price for a token
    function testShouldRevertWhenSettingInvalidPriceForToken(uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // enable trading
        vm.startPrank(admin);
        // setting any of ethAmount or tokenAmount to 0 results in invalid price error
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.enableTrading(tokens[i], ICarbonPOL.Price({ ethAmount: 0, tokenAmount: 10000 }));
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.enableTrading(tokens[i], ICarbonPOL.Price({ ethAmount: 100000, tokenAmount: 0 }));
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.enableTrading(tokens[i], ICarbonPOL.Price({ ethAmount: 0, tokenAmount: 0 }));
    }

    /// @dev test should properly return price for enabled tokens as time passes
    function testShouldProperlyReturnPriceAsTimePasses(uint128 ethAmount, uint128 tokenAmount, uint256 i) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // enable trading and set price for token
        vm.prank(admin);
        Token token = tokens[i];

        ethAmount = uint128(bound(ethAmount, 10, 1e30));
        tokenAmount = uint128(bound(tokenAmount, 10, 1e30));

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
        carbonPOL.enableTrading(token, initialPrice);

        // set timestamp to 1
        vm.warp(1);

        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token);
        uint128 expectedETHAmount = getExpectedETHAmount(ethAmount);

        assertEq(price.ethAmount, expectedETHAmount);
        assertEq(price.tokenAmount, tokenAmount);

        // price should be exactly 2x the market price at start
        assertEq(price.ethAmount, ethAmount * MARKET_PRICE_MULTIPLY_DEFAULT);

        // set timestamp to 1 day
        vm.warp(1 days);

        price = carbonPOL.tokenPrice(token);

        expectedETHAmount = getExpectedETHAmount(ethAmount);

        assertEq(price.ethAmount, expectedETHAmount);
        assertEq(price.tokenAmount, tokenAmount);

        // set timestamp to 5 days
        vm.warp(5 days);

        price = carbonPOL.tokenPrice(token);
        expectedETHAmount = getExpectedETHAmount(ethAmount);

        assertEq(price.ethAmount, expectedETHAmount);
        assertEq(price.tokenAmount, tokenAmount);

        // set timestamp to 10 days (half-life time)
        vm.warp(10 days);

        price = carbonPOL.tokenPrice(token);
        expectedETHAmount = getExpectedETHAmount(ethAmount);

        assertEq(price.ethAmount, expectedETHAmount);
        assertEq(price.tokenAmount, tokenAmount);

        // price should be equal market price +- 0.01% at half-life
        assertApproxEqRel(price.ethAmount, ethAmount, 1e14);

        // set timestamp to 15 days
        vm.warp(15 days);

        price = carbonPOL.tokenPrice(token);
        expectedETHAmount = getExpectedETHAmount(ethAmount);

        assertEq(price.ethAmount, expectedETHAmount);
        assertEq(price.tokenAmount, tokenAmount);

        // set timestamp to 20 days
        vm.warp(20 days);

        price = carbonPOL.tokenPrice(token);
        expectedETHAmount = getExpectedETHAmount(ethAmount);

        assertEq(price.ethAmount, expectedETHAmount);
        assertEq(price.tokenAmount, tokenAmount);

        // price should be equal to half the market price +- 0.01% at 2x half-life
        assertApproxEqRel(price.ethAmount, ethAmount / 2, 1e14);
    }

    /// @dev test should properly return input amount for enabled tokens as time passes
    function testShouldProperlyReturnExpectedTradeInputAmountAsTimePasses(
        uint128 ethAmount,
        uint128 tokenAmount,
        uint256 i
    ) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // enable trading and set price for token
        Token token = tokens[i];

        uint256 tokenBalance = token.balanceOf(address(carbonPOL));

        ethAmount = uint128(bound(ethAmount, 10, 1e30));
        tokenAmount = uint128(bound(tokenAmount, 10, tokenBalance));

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
        vm.prank(admin);
        carbonPOL.enableTrading(token, initialPrice);

        // set timestamp to 1
        vm.warp(1);

        // trade 1/2 of the tokens
        uint128 tradeAmount = tokenAmount / 2;

        uint128 ethForTrade = carbonPOL.expectedTradeInput(token, tradeAmount);
        uint128 expectedETHAmount = getExpectedETHToSend(token, tradeAmount);
        assertEq(ethForTrade, expectedETHAmount);

        // set timestamp to 1 day
        vm.warp(1 days);

        ethForTrade = carbonPOL.expectedTradeInput(token, tradeAmount);
        expectedETHAmount = getExpectedETHToSend(token, tradeAmount);
        assertEq(ethForTrade, expectedETHAmount);

        // set timestamp to 5 days
        vm.warp(5 days);

        ethForTrade = carbonPOL.expectedTradeInput(token, tradeAmount);
        expectedETHAmount = getExpectedETHToSend(token, tradeAmount);
        assertEq(ethForTrade, expectedETHAmount);

        // set timestamp to 10 days (half-life time)
        vm.warp(10 days);

        ethForTrade = carbonPOL.expectedTradeInput(token, tradeAmount);
        expectedETHAmount = getExpectedETHToSend(token, tradeAmount);
        assertEq(ethForTrade, expectedETHAmount);

        // set timestamp to 15 days
        vm.warp(15 days);

        ethForTrade = carbonPOL.expectedTradeInput(token, tradeAmount);
        expectedETHAmount = getExpectedETHToSend(token, tradeAmount);
        assertEq(ethForTrade, expectedETHAmount);

        // set timestamp to 20 days
        vm.warp(20 days);

        ethForTrade = carbonPOL.expectedTradeInput(token, tradeAmount);
        expectedETHAmount = getExpectedETHToSend(token, tradeAmount);
        assertEq(ethForTrade, expectedETHAmount);
    }

    /// @dev test should properly return trade output amount for enabled tokens as time passes
    function testShouldProperlyReturnExpectedTradeReturnAmountAsTimePasses(
        uint128 ethAmount,
        uint128 tokenAmount,
        uint256 i
    ) public {
        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, bnt];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 2);
        // enable trading and set price for token
        Token token = tokens[i];

        uint256 tokenBalance = token.balanceOf(address(carbonPOL));

        ethAmount = uint128(bound(ethAmount, 10, 1e30));
        tokenAmount = uint128(bound(tokenAmount, 10, tokenBalance));

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
        vm.prank(admin);
        carbonPOL.enableTrading(token, initialPrice);

        // set timestamp to 1
        vm.warp(1);

        // trade eth for 1/2 of the tokens
        uint128 ethTradeAmount = ethAmount / 2;

        uint128 tokensReceived = carbonPOL.expectedTradeReturn(token, ethTradeAmount);

        uint128 expectedTokensReceived = getExpectedTokensReceived(token, ethTradeAmount);

        assertEq(tokensReceived, expectedTokensReceived);

        // set timestamp to 1 day
        vm.warp(1 days);

        tokensReceived = carbonPOL.expectedTradeReturn(token, ethTradeAmount);

        expectedTokensReceived = getExpectedTokensReceived(token, ethTradeAmount);

        assertEq(tokensReceived, expectedTokensReceived);

        // set timestamp to 5 days
        vm.warp(5 days);

        tokensReceived = carbonPOL.expectedTradeReturn(token, ethTradeAmount);

        expectedTokensReceived = getExpectedTokensReceived(token, ethTradeAmount);

        assertEq(tokensReceived, expectedTokensReceived);

        // set timestamp to 10 days (half-life time)
        vm.warp(10 days);

        tokensReceived = carbonPOL.expectedTradeReturn(token, ethTradeAmount);

        expectedTokensReceived = getExpectedTokensReceived(token, ethTradeAmount);

        assertEq(tokensReceived, expectedTokensReceived);

        // set timestamp to 15 days
        vm.warp(15 days);

        tokensReceived = carbonPOL.expectedTradeReturn(token, ethTradeAmount);

        expectedTokensReceived = getExpectedTokensReceived(token, ethTradeAmount);

        assertEq(tokensReceived, expectedTokensReceived);

        // set timestamp to 20 days
        vm.warp(20 days);

        tokensReceived = carbonPOL.expectedTradeReturn(token, ethTradeAmount);

        expectedTokensReceived = getExpectedTokensReceived(token, ethTradeAmount);

        assertEq(tokensReceived, expectedTokensReceived);
    }

    /// @dev test trading should emit an event
    function testTradingShouldEmitAnEvent() public {
        // enable trading and set price for token1
        vm.prank(admin);
        Token token = token1;

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1000000, tokenAmount: 100000000000 });
        carbonPOL.enableTrading(token, initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 100000000;
        uint128 expectedTradeInput = carbonPOL.expectedTradeInput(token1, tradeAmount);

        // trade
        vm.expectEmit();
        emit TokenTraded(user1, token, tradeAmount, expectedTradeInput);
        carbonPOL.trade{ value: expectedTradeInput }(token, tradeAmount);

        vm.stopPrank();
    }

    /// @dev test trading should refund excess eth
    function testTradingShouldRefundExcessETH() public {
        // enable trading and set price for token1
        vm.prank(admin);
        Token token = token1;

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1000000, tokenAmount: 100000000000 });
        carbonPOL.enableTrading(token, initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 100000000;
        uint128 expectedTradeInput = carbonPOL.expectedTradeInput(token1, tradeAmount);

        uint256 ethBalanceBefore = user1.balance;

        // trade, sending twice the ETH needed for this token amount
        carbonPOL.trade{ value: expectedTradeInput * 2 }(token, tradeAmount);

        uint256 ethBalanceAfter = user1.balance;

        assertEq(ethBalanceBefore - ethBalanceAfter, expectedTradeInput);

        vm.stopPrank();
    }

    /// @dev test trading should send tokens to user
    function testTradingShouldSendTokensToUser() public {
        // enable trading and set price for token1
        vm.prank(admin);
        Token token = token1;

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1000000, tokenAmount: 100000000000 });
        carbonPOL.enableTrading(token, initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 100000000;
        uint128 expectedTradeInput = carbonPOL.expectedTradeInput(token1, tradeAmount);

        uint256 tokenBalanceBefore = token1.balanceOf(user1);

        // trade
        carbonPOL.trade{ value: expectedTradeInput }(token, tradeAmount);

        uint256 tokenBalanceAfter = token1.balanceOf(user1);

        assertEq(tokenBalanceAfter - tokenBalanceBefore, tradeAmount);

        vm.stopPrank();
    }

    /// @dev test trading should increase the contract's eth balance
    function testTradingShouldIncreaseContractBalance() public {
        // enable trading and set price for token1
        vm.prank(admin);
        Token token = token1;

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1000000, tokenAmount: 100000000000 });
        carbonPOL.enableTrading(token, initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 100000000;
        uint128 expectedTradeInput = carbonPOL.expectedTradeInput(token1, tradeAmount);

        uint256 ethBalanceBefore = address(carbonPOL).balance;

        // trade
        carbonPOL.trade{ value: expectedTradeInput }(token, tradeAmount);

        uint256 ethBalanceAfter = address(carbonPOL).balance;

        assertEq(ethBalanceAfter - ethBalanceBefore, expectedTradeInput);

        vm.stopPrank();
    }

    /// @dev test should revert getting price for tokens for which trading is disabled
    function testShouldRevertTokenPriceIfTradingIsDisabled() public {
        // expect for a revert with trading disabled
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.tokenPrice(token1);
    }

    /// @dev test should revert expected input for tokens for which trading is disabled
    function testShouldRevertExpectedTradeInputIfTradingIsDisabled(uint128 amount) public {
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token1));
        // expect for a revert with trading disabled
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.expectedTradeInput(token1, amount);
    }

    /// @dev test should revert expected return for tokens for which trading is disabled
    function testShouldRevertExpectedTradeReturnIfTradingIsDisabled(uint128 amount) public {
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token1));
        // expect for a revert with trading disabled
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.expectedTradeReturn(token1, amount);
    }

    /// @dev test should return invalid price for expected return for tokens if eth amount in price goes to zero
    function testShouldReturnInvalidPriceForExpectedTradeReturnIfEthAmountGoesToZero(uint128 amount) public {
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token1, ICarbonPOL.Price({ ethAmount: 1, tokenAmount: 1 }));
        vm.warp(20 days);
        // expect for a revert with invalid price
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.expectedTradeReturn(token1, amount);
    }

    /// @dev test should revert expected input if not enough token balance
    function testShouldRevertExpectedTradeInputIfNotEnoughTokenBalanceForTrade() public {
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token1, ICarbonPOL.Price({ ethAmount: 10000, tokenAmount: 100000000 }));
        // set timestamp to 5 days
        vm.warp(5 days);
        uint256 tokenBalance = token1.balanceOf(address(carbonPOL));
        uint128 amount = uint128(tokenBalance) + 1;
        // get expected trade input
        vm.expectRevert(ICarbonPOL.InsufficientTokenBalance.selector);
        carbonPOL.expectedTradeInput(token1, amount);
    }

    /// @dev test should revert expected return if not enough token balance
    function testShouldRevertExpectedReturnIfNotEnoughTokenBalanceForTrade() public {
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token1, ICarbonPOL.Price({ ethAmount: 10000, tokenAmount: 100000000 }));
        // set timestamp to 5 days
        vm.warp(5 days);
        // get token balance
        uint256 tokenBalance = token1.balanceOf(address(carbonPOL));
        // get expected trade input
        uint128 expectedInput = carbonPOL.expectedTradeInput(token1, uint128(tokenBalance));
        uint128 amount = expectedInput + 1;
        // expect revert
        vm.expectRevert(ICarbonPOL.InsufficientTokenBalance.selector);
        carbonPOL.expectedTradeReturn(token1, amount);
    }

    /// @dev test should revert if attempting to trade tokens for which trading is disabled
    function testShouldRevertTradingTokensForWhichTradingIsDisabled() public {
        vm.prank(user1);
        Token token = token1;
        uint128 amount = 1e18;
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token));
        // expect trade to revert
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.trade(token, amount);
    }

    /// @dev test should revert if attempting to trade eth
    function testShouldRevertTradingETH() public {
        vm.prank(user1);
        Token token = NATIVE_TOKEN;
        uint128 amount = 1e18;
        // expect trade to revert
        vm.expectRevert(ICarbonPOL.InvalidToken.selector);
        carbonPOL.trade(token, amount);
    }

    /// @dev test should revert if attempting to trade with zero amount
    function testShouldRevertTradingWithZeroAmount() public {
        Token token = token1;
        uint128 amount = 0;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token, ICarbonPOL.Price({ ethAmount: 1, tokenAmount: 1 }));
        vm.prank(user1);
        // expect trade to revert
        vm.expectRevert(ZeroValue.selector);
        carbonPOL.trade(token, amount);
    }

    /// @dev test should revert if token value in ETH is equal to 0
    function testShouldRevertTradingForZeroTokenValue() public {
        Token token = token1;
        // trade 999 tokens
        uint128 amount = 999;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token, ICarbonPOL.Price({ ethAmount: 1, tokenAmount: 1000 }));
        vm.startPrank(user1);
        // set block.timestamp to 1000
        vm.warp(1000);
        // expect eth required to be 0
        assertEq(carbonPOL.expectedTradeInput(token, amount), 0);
        // expect trade to revert
        vm.expectRevert(ICarbonPOL.InvalidTrade.selector);
        carbonPOL.trade(token, amount);
        vm.stopPrank();
    }

    /// @dev test should revert trading if not enough eth has been sent
    function testShouldRevertTradingIfNotEnoughETHSent() public {
        Token token = token1;
        // trade 1e18 tokens
        uint128 amount = 1e18;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token, ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 1e22 }));
        vm.startPrank(user1);
        // set timestamp to 1000 to ensure some time passes between calls
        vm.warp(1000);
        // expect eth required to be greater than 0
        uint128 ethRequired = carbonPOL.expectedTradeInput(token, amount);
        assertGt(ethRequired, 0);
        // expect trade to revert
        vm.expectRevert(ICarbonPOL.InsufficientNativeTokenSent.selector);
        // send one wei less than required
        carbonPOL.trade{ value: ethRequired - 1 }(token, amount);
        vm.stopPrank();
    }

    /// @dev helper function to get expected eth amount in price for a token at the current time
    function getExpectedETHAmount(uint128 ethAmount) private view returns (uint128) {
        // calculate the actual price by multiplying the eth amount by the factor
        ethAmount *= carbonPOL.marketPriceMultiply();
        uint32 tradingStartTime = 1;
        // get time elapsed since trading was enabled
        uint32 timeElapsed = uint32(block.timestamp) - tradingStartTime;
        uint32 priceDecayHalfLife = carbonPOL.priceDecayHalfLife();
        // get the current eth amount by adjusting the eth amount with the exp decay formula
        ethAmount = uint128(ExpDecayMath.calcExpDecay(ethAmount, timeElapsed, priceDecayHalfLife));
        return ethAmount;
    }

    /// @dev helper function to get expected eth amount to send given a token amount
    function getExpectedETHToSend(Token token, uint128 tokenAmount) private view returns (uint128 ethAmount) {
        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token);
        // multiply the token amount by the eth amount / total eth amount ratio to get the actual tokens received
        return uint128(MathEx.mulDivF(price.ethAmount, tokenAmount, price.tokenAmount));
    }

    /// @dev helper function to get expected token amount to send given an eth amount
    function getExpectedTokensReceived(Token token, uint128 ethAmount) private view returns (uint128 tokenAmount) {
        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token);
        // multiply the token amount by the eth amount / total eth amount ratio to get the actual tokens received
        return uint128(MathEx.mulDivF(price.tokenAmount, ethAmount, price.ethAmount));
    }
}
