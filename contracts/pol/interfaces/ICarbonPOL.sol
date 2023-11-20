// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @notice CarbonPOL interface
 */
interface ICarbonPOL is IUpgradeable {
    error InvalidToken();
    error InvalidPrice();
    error InvalidTrade();
    error TradingDisabled();
    error InsufficientNativeTokenSent();
    error InsufficientAmountForTrading();

    struct Price {
        uint128 sourceAmount;
        uint128 targetAmount;
    }

    struct EthSaleAmount {
        uint128 initial;
        uint128 current;
    }

    /**
     * @notice triggered when trading is enabled for a token
     */
    event TradingEnabled(Token indexed token, Price price);

    /**
     * @notice triggered after a successful trade is executed
     */
    event TokenTraded(address indexed caller, Token indexed token, uint128 inputAmount, uint128 outputAmount);

    /**
     * @notice triggered after an eth trade leaves less than 10% of the initial eth sale amount
     */
    event PriceUpdated(Token indexed token, Price price);

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
     * @notice returns the market price multiplier
     */
    function marketPriceMultiply() external view returns (uint32);

    /**
     * @notice returns the price decay half-life according to the exp decay formula
     */
    function priceDecayHalfLife() external view returns (uint32);

    /**
     * @notice returns the initial and current eth sale amount
     */
    function ethSaleAmount() external view returns (EthSaleAmount memory);

    /**
     * @notice returns true if trading is enabled for token
     */
    function tradingEnabled(Token token) external view returns (bool);

    /**
     * @notice returns the amount available for trading for the token
     */
    function amountAvailableForTrading(Token token) external view returns (uint128);

    /**
     * @notice returns the expected trade output (tokens received) given an token amount sent
     */
    function expectedTradeReturn(Token token, uint128 ethAmount) external view returns (uint128 tokenAmount);

    /**
     * @notice returns the expected trade input (how many tokens to send) given a token amount received
     */
    function expectedTradeInput(Token token, uint128 tokenAmount) external view returns (uint128 ethAmount);

    /**
     * @notice returns the current token price (ETH / TKN)
     * @notice if token == ETH, returns BNT / ETH price
     */
    function tokenPrice(Token token) external view returns (Price memory price);

    /**
     * @notice trades ETH for *amount* of token based on the current token price (trade by target amount)
     * @notice if token == ETH, trades BNT for amount of ETH
     */
    function trade(Token token, uint128 amount) external payable;
}
