// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { POLTestCaseParser } from "./POLTestCaseParser.t.sol";

import { AccessDenied, ZeroValue, InvalidAddress } from "../../contracts/utility/Utils.sol";
import { Token, toERC20, NATIVE_TOKEN } from "../../contracts/token/Token.sol";
import { TestReenterCarbonPOL } from "../../contracts/helpers/TestReenterCarbonPOL.sol";

import { ICarbonPOL } from "../../contracts/pol/interfaces/ICarbonPOL.sol";
import { CarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

contract CarbonPOLTest is TestFixture {
    using Address for address payable;

    // Test case parser helper
    POLTestCaseParser private testCaseParser;

    uint32 private constant MARKET_PRICE_MULTIPLY_DEFAULT = 2;
    uint32 private constant MARKET_PRICE_MULTIPLY_UPDATED = 3;

    uint32 private constant PRICE_DECAY_HALFLIFE_DEFAULT = 10 days;
    uint32 private constant PRICE_DECAY_HALFLIFE_UPDATED = 15 days;

    uint128 private constant ETH_SALE_AMOUNT_DEFAULT = 100 ether;
    uint128 private constant ETH_SALE_AMOUNT_UPDATED = 150 ether;

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
     * @notice triggered after an eth sale leaves less than 10% of the initial eth sale amount
     */
    event PriceUpdated(Token indexed token, ICarbonPOL.Price price);

    /**
     * @notice triggered when the market price multiplier is updated
     */
    event MarketPriceMultiplyUpdated(uint32 prevMarketPriceMultiply, uint32 newMarketPriceMultiply);

    /**
     * @notice triggered when the price decay halflife is updated
     */
    event PriceDecayHalfLifeUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the eth sale amount is updated
     */
    event EthSaleAmountUpdated(uint128 prevEthSaleAmount, uint128 newEthSaleAmount);

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
        // Deploy test case parser
        testCaseParser = new POLTestCaseParser();
    }

    function testShouldBeInitialized() public {
        uint16 version = carbonPOL.version();
        assertEq(version, 2);
    }

    function testShouldntBeAbleToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        carbonPOL.initialize();
    }

    /**
     * @dev test should revert when deploying CarbonPOL with an invalid bnt address
     */
    function testShouldRevertWhenDeployingWithInvalidBNTAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonPOL(Token.wrap(address(0)));
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
    function testShouldRevertSettingThePriceDecayHalfLifeWithAnInvalidFee() public {
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
     * @dev eth sale amount tests
     */

    /// @dev test that setEthSaleAmount should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheEthSaleAmount() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.setEthSaleAmount(ETH_SALE_AMOUNT_UPDATED);
    }

    /// @dev test that setEthSaleAmount should revert when setting to an invalid value
    function testShouldRevertSettingTheEthSaleAmountWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonPOL.setEthSaleAmount(0);
    }

    /// @dev test that setEthSaleAmount with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameEthSaleAmount() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit EthSaleAmountUpdated(ETH_SALE_AMOUNT_DEFAULT, ETH_SALE_AMOUNT_DEFAULT);
        carbonPOL.setEthSaleAmount(ETH_SALE_AMOUNT_DEFAULT);
    }

    /// @dev test that admin should be able to update the eth sale amount
    function testShouldBeAbleToSetAndUpdateTheEthSaleAmount() public {
        vm.startPrank(admin);
        uint128 ethSaleAmount = carbonPOL.ethSaleAmount();
        assertEq(ethSaleAmount, ETH_SALE_AMOUNT_DEFAULT);

        vm.expectEmit();
        emit EthSaleAmountUpdated(ETH_SALE_AMOUNT_DEFAULT, ETH_SALE_AMOUNT_UPDATED);
        carbonPOL.setEthSaleAmount(ETH_SALE_AMOUNT_UPDATED);

        ethSaleAmount = carbonPOL.ethSaleAmount();
        assertEq(ethSaleAmount, ETH_SALE_AMOUNT_UPDATED);
        vm.stopPrank();
    }

    /// @dev test that setting the eth sale amount to an amount below the current eth sale amount reset the current amount
    function testCurrentEthSaleAmountIsUpdatedWhenAboveTheNewEthSaleAmount() public {
        vm.startPrank(admin);
        uint128 ethSaleAmount = carbonPOL.ethSaleAmount();
        assertEq(ethSaleAmount, ETH_SALE_AMOUNT_DEFAULT);

        // enable trading to set the current eth sale amount
        ICarbonPOL.Price memory price = ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 });
        carbonPOL.enableTradingETH(price);

        // assert current and max amounts are equal
        uint128 currentEthSaleAmount = carbonPOL.currentEthSaleAmount();
        assertEq(currentEthSaleAmount, ethSaleAmount);

        // set the new amount to amount / 2
        uint128 newSaleAmount = ETH_SALE_AMOUNT_DEFAULT / 2;
        carbonPOL.setEthSaleAmount(newSaleAmount);

        // assert both amounts are updated
        ethSaleAmount = carbonPOL.ethSaleAmount();
        currentEthSaleAmount = carbonPOL.currentEthSaleAmount();
        assertEq(ethSaleAmount, currentEthSaleAmount);
        vm.stopPrank();
    }

    /**
     * @dev trading tests
     */

    /// @dev test trading should be disabled initially for all tokens
    function testTradingShouldBeDisabledInitially(uint256 i) public {
        // pick one of these tokens to test
        Token[4] memory tokens = [token1, token2, bnt, NATIVE_TOKEN];
        // pick a random number from 0 to 2 for the tokens
        i = bound(i, 0, 3);
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

    /// @dev test non admin shouldn't be able to enable eth trading
    function testNonAdminShouldntBeAbleToEnableTradingETH() public {
        // enable trading
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 }));
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

    /// @dev test admin should be able to enable eth trading
    function testAdminShouldBeAbleToEnableTradingETH() public {
        // enable trading
        vm.prank(admin);
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 }));
        // assert trading is enabled
        assertTrue(carbonPOL.tradingEnabled(NATIVE_TOKEN));
        // check current eth sale amount is set to the initial eth sale amount
        assertEq(carbonPOL.ethSaleAmount(), carbonPOL.currentEthSaleAmount());
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

    /// @dev test enabling trading for eth should emit an event
    function testEnablingTradingForETHShouldEmitAnEvent() public {
        ICarbonPOL.Price memory price = ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 });
        vm.prank(admin);
        // expect event to be emitted
        vm.expectEmit();
        emit TradingEnabled(NATIVE_TOKEN, price);
        // enable trading
        carbonPOL.enableTradingETH(price);
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

    /// @dev test should revert when setting invalid price for the native token
    function testShouldRevertWhenSettingInvalidPriceForNativeToken() public {
        // enable trading
        vm.startPrank(admin);
        // setting any of ethAmount or tokenAmount to 0 results in invalid price error
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 0, tokenAmount: 10000 }));
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 100000, tokenAmount: 0 }));
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 0, tokenAmount: 0 }));
    }

    /// @dev test should revert when enabling trading for the native token using enableTrading
    function testShouldRevertWhenEnablingTradingForNativeTokenUsingEnableTrading() public {
        // enable trading
        vm.startPrank(admin);
        // attempting to enable trading using enable trading for native token should revert
        vm.expectRevert(ICarbonPOL.InvalidToken.selector);
        carbonPOL.enableTrading(NATIVE_TOKEN, ICarbonPOL.Price({ ethAmount: 100, tokenAmount: 10000 }));
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
        // price should be exactly 2x the market price at start
        assertEq(price.ethAmount, ethAmount * MARKET_PRICE_MULTIPLY_DEFAULT);

        // set timestamp to 10 days (half-life time)
        vm.warp(10 days + 1);

        // price should be equal market price at half-life
        price = carbonPOL.tokenPrice(token);
        assertEq(price.ethAmount, ethAmount);

        // set timestamp to 20 days
        vm.warp(20 days + 1);

        // price should be equal to half the market price at 2x half-life
        price = carbonPOL.tokenPrice(token);
        assertEq(price.ethAmount, ethAmount / 2);
    }

    /// @dev test should properly return price for native token as time passes
    function testShouldProperlyReturnNativeTokenPriceAsTimePasses(uint128 ethAmount, uint128 tokenAmount) public {
        // enable trading and set price for token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        ethAmount = uint128(bound(ethAmount, 10, 1e30));
        tokenAmount = uint128(bound(tokenAmount, 10, 1e30));

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
        carbonPOL.enableTradingETH(initialPrice);

        // set timestamp to 1
        vm.warp(1);

        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token);
        // price should be exactly 2x the market price at start
        assertEq(price.tokenAmount, tokenAmount * MARKET_PRICE_MULTIPLY_DEFAULT);

        // set timestamp to 10 days (half-life time)
        vm.warp(10 days + 1);

        // price should be equal market price at half-life
        price = carbonPOL.tokenPrice(token);
        assertEq(price.tokenAmount, tokenAmount);

        // set timestamp to 20 days
        vm.warp(20 days + 1);

        // price should be equal to half the market price at 2x half-life
        price = carbonPOL.tokenPrice(token);
        assertEq(price.tokenAmount, tokenAmount / 2);
    }

    /// @dev test should properly return price for native token as time passes
    function testShouldProperlyReturnNativeTokenPriceAfterBigSale(uint128 ethAmount, uint128 tokenAmount) public {
        // enable trading and set price for token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        ethAmount = uint128(bound(ethAmount, 1e17, 1 * 1e18));
        tokenAmount = uint128(bound(tokenAmount, 1000 * 1e18, 4000 * 1e18));

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 1
        vm.warp(1);

        // set timestamp to 10 days
        vm.warp(10 days + 1);

        // trade 95% of the eth sale amount
        uint128 currentEthSaleAmount = uint128(carbonPOL.currentEthSaleAmount());
        uint128 ethTradeAmount = (currentEthSaleAmount * 95) / 100;
        uint128 tradeAmount = carbonPOL.expectedTradeReturn(token, ethTradeAmount);
        bnt.safeApprove(address(carbonPOL), tradeAmount);
        carbonPOL.trade(token, tradeAmount);

        // price has been reset at this point

        // get price after reset
        ICarbonPOL.Price memory price = carbonPOL.tokenPrice(token);

        // set timestamp to 20 days (half-life time)
        vm.warp(20 days + 1);

        ICarbonPOL.Price memory newPrice = carbonPOL.tokenPrice(token);
        // new price should be exactly equal to the prev price / 2 after the update
        assertEq(price.ethAmount, newPrice.ethAmount);
        assertEq(price.tokenAmount, newPrice.tokenAmount * carbonPOL.marketPriceMultiply());
    }

    /// @dev test correct prices retrieved by tokenPrice with different initial prices and different timestamps
    function testPricesAtTimestamps() public {
        // test the following timestamps, ethAmounts and tokenAmounts
        uint24[10] memory timestamps = [
            1,
            1 days,
            2 days,
            5 days,
            10 days,
            20 days,
            30 days,
            40 days,
            50 days,
            100 days
        ];
        uint88[10] memory ethAmounts = [
            100,
            1e18,
            10e18,
            1000e18,
            10000e18,
            100000e18,
            500000e18,
            1000000e18,
            5000000e18,
            10000000e18
        ];
        uint88[10] memory tokenAmounts = [
            100,
            1e18,
            10e18,
            1000e18,
            10000e18,
            100000e18,
            500000e18,
            1000000e18,
            5000000e18,
            10000000e18
        ];
        // enable trading and set price for token
        vm.startPrank(admin);
        Token token = token1;

        // get test cases from the pol test case parser
        POLTestCaseParser.TestCase[] memory testCases = testCaseParser.getTestCases(false);

        // go through each of the eth amounts, token amounts and timestamps to verify token price output matches test data
        for (uint256 i = 0; i < ethAmounts.length; ++i) {
            for (uint256 j = 0; j < tokenAmounts.length; ++j) {
                vm.warp(1);
                uint128 ethAmount = uint128(ethAmounts[i]);
                uint128 tokenAmount = uint128(tokenAmounts[j]);
                ICarbonPOL.Price memory price = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
                carbonPOL.enableTrading(token1, price);
                // get the correct test case for this price
                POLTestCaseParser.TestCase memory currentCase;
                for (uint256 t = 0; t < testCases.length; ++t) {
                    if (
                        testCases[t].initialPrice.ethAmount == ethAmount &&
                        testCases[t].initialPrice.tokenAmount == tokenAmount
                    ) {
                        currentCase = testCases[t];
                    }
                }
                for (uint256 k = 0; k < timestamps.length; ++k) {
                    // set timestamp
                    vm.warp(timestamps[k]);
                    // get token price at this timestamp
                    price = carbonPOL.tokenPrice(token);
                    // get test data for this timestamp
                    POLTestCaseParser.PriceAtTimestamp memory priceAtTimestamp = currentCase.pricesAtTimestamp[k];
                    // assert test data matches the actual token price data
                    assertEq(priceAtTimestamp.timestamp, timestamps[k]);
                    assertEq(priceAtTimestamp.ethAmount, price.ethAmount);
                    assertEq(priceAtTimestamp.tokenAmount, price.tokenAmount);
                }
            }
        }
    }

    /// @dev test correct prices for ETH retrieved by tokenPrice with different initial prices and different timestamps
    function testETHPricesAtTimestamps() public {
        // test the following timestamps, ethAmounts and tokenAmounts
        uint24[10] memory timestamps = [
            1,
            1 days,
            2 days,
            5 days,
            10 days,
            20 days,
            30 days,
            40 days,
            50 days,
            100 days
        ];
        uint72[5] memory ethAmounts = [100, 1e18, 100e18, 10e18, 1000e18];
        uint80[11] memory tokenAmounts = [
            100,
            1e18,
            10e18,
            100e18,
            1000e18,
            1200e18,
            1500e18,
            2000e18,
            2400e18,
            3000e18,
            10000e18
        ];
        // enable trading and set price for token
        vm.startPrank(admin);
        Token token = NATIVE_TOKEN;

        // get test cases from the pol test case parser
        POLTestCaseParser.TestCase[] memory testCases = testCaseParser.getTestCases(true);

        // go through each of the eth amounts, token amounts and timestamps to verify token price output matches test data
        for (uint256 i = 0; i < ethAmounts.length; ++i) {
            for (uint256 j = 0; j < tokenAmounts.length; ++j) {
                vm.warp(1);
                uint128 ethAmount = uint128(ethAmounts[i]);
                uint128 tokenAmount = uint128(tokenAmounts[j]);
                ICarbonPOL.Price memory price = ICarbonPOL.Price({ ethAmount: ethAmount, tokenAmount: tokenAmount });
                carbonPOL.enableTradingETH(price);
                // get the correct test case for this price
                POLTestCaseParser.TestCase memory currentCase;
                for (uint256 t = 0; t < testCases.length; ++t) {
                    if (
                        testCases[t].initialPrice.ethAmount == ethAmount &&
                        testCases[t].initialPrice.tokenAmount == tokenAmount
                    ) {
                        currentCase = testCases[t];
                    }
                }
                for (uint256 k = 0; k < timestamps.length; ++k) {
                    // set timestamp
                    vm.warp(timestamps[k]);
                    // get token price at this timestamp
                    price = carbonPOL.tokenPrice(token);
                    // get test data for this timestamp
                    POLTestCaseParser.PriceAtTimestamp memory priceAtTimestamp = currentCase.pricesAtTimestamp[k];
                    // assert test data matches the actual token price data
                    assertEq(priceAtTimestamp.timestamp, timestamps[k]);
                    assertEq(priceAtTimestamp.ethAmount, price.ethAmount);
                    assertEq(priceAtTimestamp.tokenAmount, price.tokenAmount);
                }
            }
        }
    }

    /// @dev test trading tokens should emit an event
    function testTradingTokensShouldEmitAnEvent() public {
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

    /// @dev test trading eth should emit an event
    function testTradingETHShouldEmitAnEvent() public {
        // enable trading and set price for the native token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1000000, tokenAmount: 100000000000 });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 100000000;
        uint128 expectedTradeInput = carbonPOL.expectedTradeInput(token, tradeAmount);

        // approve bnt for eth -> bnt trades
        bnt.safeApprove(address(carbonPOL), tradeAmount);

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

    /// @dev test trading eth should send eth to user
    function testTradingETHShouldSendETHToUser() public {
        // enable trading and set price for the native token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        // set 1 eth = 2000 bnt as initial price
        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 2000 * 1e18 });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 1000e18;
        uint128 expectedEthReceived = carbonPOL.expectedTradeInput(token, tradeAmount);

        uint256 ethBalanceBefore = user1.balance;

        // approve bnt for eth -> bnt trades
        bnt.safeApprove(address(carbonPOL), tradeAmount);

        // trade
        carbonPOL.trade(token, tradeAmount);

        uint256 ethBalanceAfter = user1.balance;

        assertEq(ethBalanceAfter - ethBalanceBefore, expectedEthReceived);

        vm.stopPrank();
    }

    /// @dev test trading eth should burn bnt
    function testTradingETHShouldBurnBNT() public {
        // enable trading and set price for the native token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        // set 1 eth = 2000 bnt as initial price
        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 2000 * 1e18 });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 1000 * 1e18;
        uint128 expectedTradeInput = carbonPOL.expectedTradeInput(token, tradeAmount);

        uint256 bntBalanceBefore = bnt.balanceOf(user1);
        uint256 bntSupplyBefore = toERC20(bnt).totalSupply();

        // approve bnt for eth -> bnt trades
        bnt.safeApprove(address(carbonPOL), tradeAmount);

        // trade
        carbonPOL.trade{ value: expectedTradeInput }(token, tradeAmount);

        uint256 bntBalanceAfter = bnt.balanceOf(user1);
        uint256 bntSupplyAfter = toERC20(bnt).totalSupply();

        assertEq(bntBalanceBefore - bntBalanceAfter, tradeAmount);
        assertEq(bntSupplyBefore - bntSupplyAfter, tradeAmount);

        vm.stopPrank();
    }

    /// @dev test trading eth should decrease the current eth sale amount
    function testTradingETHShouldDecreaseCurrentEthSaleAmount() public {
        // enable trading and set price for the native token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        // set 1 eth = 2000 bnt as initial price
        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 2000 * 1e18 });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // expected trade input
        uint128 tradeAmount = 4000 * 1e18;
        uint128 expectedEthReceived = carbonPOL.expectedTradeInput(token, tradeAmount);

        uint128 saleAmountBefore = carbonPOL.currentEthSaleAmount();

        // approve bnt for eth -> bnt trades
        bnt.safeApprove(address(carbonPOL), tradeAmount);

        // trade
        carbonPOL.trade(token, tradeAmount);

        uint128 saleAmountAfter = carbonPOL.currentEthSaleAmount();

        assertEq(saleAmountBefore - saleAmountAfter, expectedEthReceived);

        vm.stopPrank();
    }

    /// @dev test trading eth below the 10% * sale amount threshold should reset the price and current eth amount
    function testTradingETHBelowTheSaleThreshholdShouldResetThePriceAndCurrentEthAmount() public {
        // enable trading and set price for the native token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        // set 1 eth = 2000 bnt as initial price
        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 2000 * 1e18 });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // trade 85% of the sale amount
        uint128 initialSaleAmount = carbonPOL.ethSaleAmount();
        uint128 currentSaleAmount = carbonPOL.currentEthSaleAmount();

        // assert current and initial eth sale amount are equal
        assertEq(initialSaleAmount, currentSaleAmount);

        uint128 amountToSell = uint128((initialSaleAmount * 85) / 100);

        uint128 tradeAmount = carbonPOL.expectedTradeReturn(token, amountToSell);
        uint128 ethSale = carbonPOL.expectedTradeInput(token, tradeAmount);

        // assert that the expected eth sale for the bnt amount is equal to 85% of the initialSaleAmount
        assertEq(ethSale, amountToSell);

        // approve bnt for eth -> bnt trades
        bnt.safeApprove(address(carbonPOL), MAX_SOURCE_AMOUNT);

        // trade
        carbonPOL.trade(token, tradeAmount);

        // assert we have 15% available eth for sale
        currentSaleAmount = carbonPOL.currentEthSaleAmount();
        assertEq(currentSaleAmount, initialSaleAmount - ethSale);

        // get the price before the threshold trade
        ICarbonPOL.Price memory prevPrice = carbonPOL.tokenPrice(NATIVE_TOKEN);

        // trade 10% more (so that we go below 10% of the max sale amount)
        amountToSell = uint128((initialSaleAmount * 10) / 100);
        tradeAmount = carbonPOL.expectedTradeReturn(token, amountToSell);
        carbonPOL.trade(token, tradeAmount);

        // assert initial sale amount is the same
        assertEq(initialSaleAmount, carbonPOL.ethSaleAmount());

        // assert new current eth sale amount is equal to the initial (we have topped up the amount)
        currentSaleAmount = carbonPOL.currentEthSaleAmount();
        assertEq(currentSaleAmount, initialSaleAmount);

        vm.warp(block.timestamp + 1);
        // get the price after the threshold trade
        ICarbonPOL.Price memory newPrice = carbonPOL.tokenPrice(NATIVE_TOKEN);

        // assert new price is twice the price before the trade
        assertEq(newPrice.ethAmount, prevPrice.ethAmount);
        assertEq(newPrice.tokenAmount, prevPrice.tokenAmount * carbonPOL.marketPriceMultiply());

        vm.stopPrank();
    }

    /// @dev test trading eth below the 10% * sale amount threshold should emit price updated event
    function testTradingETHBelowTheSaleThreshholdShouldEmitEvent() public {
        // enable trading and set price for the native token
        vm.prank(admin);
        Token token = NATIVE_TOKEN;

        // set 1 eth = 2000 bnt as initial price
        ICarbonPOL.Price memory initialPrice = ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 2000 * 1e18 });
        carbonPOL.enableTradingETH(initialPrice);

        vm.startPrank(user1);

        // set timestamp to 10 days
        vm.warp(10 days);

        // trade 95% of the sale amount
        uint128 initialSaleAmount = carbonPOL.ethSaleAmount();
        uint128 currentSaleAmount = carbonPOL.currentEthSaleAmount();

        // assert current and initial eth sale amount are equal
        assertEq(initialSaleAmount, currentSaleAmount);

        uint128 amountToSell = uint128((initialSaleAmount * 95) / 100);

        uint128 tradeAmount = carbonPOL.expectedTradeReturn(token, amountToSell);
        uint128 ethSale = carbonPOL.expectedTradeInput(token, tradeAmount);

        // assert that the expected eth sale for the bnt amount is equal to 85% of the initialSaleAmount
        assertEq(ethSale, amountToSell);

        // approve bnt for eth -> bnt trades
        bnt.safeApprove(address(carbonPOL), MAX_SOURCE_AMOUNT);

        // get the price before the threshold trade
        ICarbonPOL.Price memory prevPrice = carbonPOL.tokenPrice(NATIVE_TOKEN);

        uint128 newExpectedTokenAmount = prevPrice.tokenAmount * carbonPOL.marketPriceMultiply();
        ICarbonPOL.Price memory newExpectedPrice = ICarbonPOL.Price({
            ethAmount: prevPrice.ethAmount,
            tokenAmount: newExpectedTokenAmount
        });

        // trade
        vm.expectEmit();
        emit PriceUpdated(token, newExpectedPrice);
        carbonPOL.trade(token, tradeAmount);

        vm.stopPrank();
    }

    /// @dev test should revert getting price for tokens for which trading is disabled
    function testShouldRevertTokenPriceIfTradingIsDisabled(bool isNativeToken) public {
        Token token = isNativeToken ? NATIVE_TOKEN : token1;
        // expect for a revert with trading disabled
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.tokenPrice(token);
    }

    /// @dev test should revert expected input for tokens for which trading is disabled
    function testShouldRevertExpectedTradeInputIfTradingIsDisabled(bool isNativeToken, uint128 amount) public {
        Token token = isNativeToken ? NATIVE_TOKEN : token1;
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token));
        // expect for a revert with trading disabled
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.expectedTradeInput(token, amount);
    }

    /// @dev test should revert expected return for tokens for which trading is disabled
    function testShouldRevertExpectedTradeReturnIfTradingIsDisabled(bool isNativeToken, uint128 amount) public {
        Token token = isNativeToken ? NATIVE_TOKEN : token1;
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token));
        // expect for a revert with trading disabled
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
        carbonPOL.expectedTradeReturn(token, amount);
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

    /// @dev test should return invalid price for expected return for native token if eth amount in price goes to zero
    function testShouldReturnInvalidPriceForExpectedTradeReturnForNativeTokenIfEthAmountGoesToZero(
        uint128 amount
    ) public {
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 1, tokenAmount: 1 }));
        vm.warp(20 days);
        // expect for a revert with invalid price
        vm.expectRevert(ICarbonPOL.InvalidPrice.selector);
        carbonPOL.expectedTradeReturn(NATIVE_TOKEN, amount);
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

    /// @dev test should revert expected input for native token if not enough token balance
    function testShouldRevertExpectedTradeInputIfNotEnoughNativeTokenBalanceForTrade() public {
        vm.prank(admin);
        // enable native token to test
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 10000, tokenAmount: 100000000 }));
        // set timestamp to 5 days
        vm.warp(5 days);
        uint256 ethBalance = NATIVE_TOKEN.balanceOf(address(carbonPOL));
        uint128 maxTokenAmount = carbonPOL.expectedTradeReturn(NATIVE_TOKEN, uint128(ethBalance));
        uint128 amount = maxTokenAmount + 1e18;
        // get expected trade input
        vm.expectRevert(ICarbonPOL.InsufficientTokenBalance.selector);
        carbonPOL.expectedTradeInput(NATIVE_TOKEN, amount);
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

    /// @dev test should revert expected return if not enough token balance
    function testShouldRevertExpectedReturnIfNotEnoughNativeTokenBalanceForTrade() public {
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token1, ICarbonPOL.Price({ ethAmount: 10000, tokenAmount: 100000000 }));
        // set timestamp to 5 days
        vm.warp(5 days);
        // get token balance
        uint256 tokenBalance = token1.balanceOf(address(carbonPOL));
        uint128 amount = uint128(tokenBalance) + 1;
        // expect revert
        vm.expectRevert(ICarbonPOL.InsufficientTokenBalance.selector);
        carbonPOL.expectedTradeReturn(token1, amount);
    }

    /// @dev test should revert if attempting to trade tokens for which trading is disabled
    function testShouldRevertTradingTokensForWhichTradingIsDisabled(bool isNativeToken) public {
        vm.prank(user1);
        Token token = isNativeToken ? NATIVE_TOKEN : token1;
        uint128 amount = 1e18;
        // assert trading is disabled for token
        assertFalse(carbonPOL.tradingEnabled(token));
        // expect trade to revert
        vm.expectRevert(ICarbonPOL.TradingDisabled.selector);
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

    /// @dev test should revert if attempting to trade native token with zero amount
    function testShouldRevertTradingNativeTokenWithZeroAmount() public {
        Token token = NATIVE_TOKEN;
        uint128 amount = 0;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 1, tokenAmount: 1 }));
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

    /// @dev test should revert trading eth if BNT to send is equal to 0
    function testShouldRevertTradingETHForZeroTokenValue() public {
        Token token = NATIVE_TOKEN;
        // trade 999 tokens
        uint128 amount = 999;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 1, tokenAmount: 1000 }));
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

    /// @dev test should revert trading eth if the trade amount is above the current eth sale amount
    function testShouldRevertTradingETHIfTradeAmountIsAboveCurrentEthSaleAmount() public {
        Token token = NATIVE_TOKEN;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTradingETH(ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 2000 * 1e18 }));

        // assert that available eth amount is exactly 100 ether
        assertEq(carbonPOL.currentEthSaleAmount(), 100 ether);

        vm.startPrank(user1);

        // check 100 eth trade passes successfully
        uint128 maxTradeTokenAmount = carbonPOL.expectedTradeReturn(token, 100 ether);
        bnt.safeApprove(address(carbonPOL), maxTradeTokenAmount);
        carbonPOL.trade(token, maxTradeTokenAmount);

        // set block.timestamp to 1000
        vm.warp(1000);
        // trade a bit over 100 eth
        uint128 ethAmount = 100 ether + 2;
        uint128 tokenAmount = carbonPOL.expectedTradeReturn(token, ethAmount);

        // assert that the eth amount for *tokenAmount* is exactly 1 wei above 100 eth and should revert the trade
        uint128 expectedEthAmount = carbonPOL.expectedTradeInput(token, tokenAmount);
        assertEq(expectedEthAmount, 100 ether + 1);
        assertGt(expectedEthAmount, carbonPOL.currentEthSaleAmount());

        // expect trade to revert
        vm.expectRevert(ICarbonPOL.InsufficientEthForSale.selector);
        carbonPOL.trade(token, tokenAmount);
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

    /// @dev test should revert trading if reentrancy is attempted
    function testShouldRevertTradingIfReentrancyIsAttempted() public {
        Token token = token1;
        // trade 1e18 tokens
        uint128 amount = 1e18;
        vm.prank(admin);
        // enable token to test
        carbonPOL.enableTrading(token, ICarbonPOL.Price({ ethAmount: 1e18, tokenAmount: 1e22 }));
        vm.startPrank(user1);
        // deploy carbonPOL reentrancy contract
        TestReenterCarbonPOL testReentrancy = new TestReenterCarbonPOL(carbonPOL, token);

        // set timestamp to 1000 to ensure some time passes between calls
        vm.warp(1000);
        // expect eth required to be greater than 0
        uint128 ethRequired = carbonPOL.expectedTradeInput(token, amount);
        assertGt(ethRequired, 0);
        // expect trade to revert
        // reverts in "sendValue" in trade in carbonPOL
        vm.expectRevert("Address: unable to send value, recipient may have reverted");
        // send a bit more eth in order to refund the contract, so "receive" is called
        testReentrancy.tryReenterCarbonPOL{ value: ethRequired + 1 }(amount);
        vm.stopPrank();
    }
}
