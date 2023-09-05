// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { CarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

import { AccessDenied, InvalidAddress, InvalidFee, ZeroValue } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";
import { MathEx } from "../../contracts/utility/MathEx.sol";
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

    /// @dev test should properly return price for enabled token
    function testShouldProperlyReturnPriceForEnabledTokens() public {
        // enable trading and set price for token1
        vm.prank(admin);
        Token token = token1;

        uint128 ethAmount = 1000000;
        uint128 tokenAmount = 100000000000;

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
        carbonPOL.enableTrading(token, initialPrice);

        uint32 halfLifeDecay = carbonPOL.priceDecayHalfLife();
        // set timestamp to half-life duration
        vm.warp(halfLifeDecay);

        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token);

        ICarbonPOL.Price memory expectedPrice = ICarbonPOL.Price({
            ethAmount: ethAmount - 1,
            tokenAmount: tokenAmount
        });

        assertEq(price.ethAmount, expectedPrice.ethAmount);
        assertEq(price.tokenAmount, expectedPrice.tokenAmount);
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

    /// @dev test should return 0 price for tokens for which trading is disabled
    function testShouldReturnZeroPriceIfTradingIsDisabled() public {
        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token1);
        assertEq(0, price.tokenAmount);
        assertEq(0, price.ethAmount);
    }

    /// @dev test should return 0 expected input for tokens for which trading is disabled
    function testShouldReturnZeroExpectedTradeInputIfTradingIsDisabled(uint128 amount) public {
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token1));
        // get expected trade input
        uint128 expectedInput = carbonPOL.expectedTradeInput(token1, amount);
        assertEq(0, expectedInput);
    }

    /// @dev test should return 0 expected return for tokens for which trading is disabled
    function testShouldReturnZeroExpectedTradeReturnIfTradingIsDisabled(uint128 amount) public {
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token1));
        // get expected trade return
        uint128 expectedReturn = carbonPOL.expectedTradeReturn(token1, amount);
        assertEq(0, expectedReturn);
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

    /// @dev test should revert on attempt to trade in the same block in which trading is enabled
    function testShouldRevertTradingInSameBlockAsTradingIsEnabled() public {
        Token token = token1;
        // trade 1000000000 tokens
        uint128 amount = 1000000000;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token, ICarbonPOL.Price({ ethAmount: 1000000000, tokenAmount: 1000000000000 }));
        vm.startPrank(user1);
        // expect eth required to be 0 - since no time has passed since enabling the trade
        // the get price function returns ethAmount as 0 and eth required is also 0
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
}
