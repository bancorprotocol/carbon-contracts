// SPDX-License-Identifier: BUSL-1.1
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
    error InsufficientTokenBalance();

    struct Price {
        uint128 ethAmount;
        uint128 tokenAmount;
    }

    /**
     * @notice triggered when trading is enabled for a token
     */
    event TradingEnabled(Token indexed token, Price price);

    /**
     * @notice triggered after a successful trade is executed
     */
    event TokenTraded(
        address indexed caller,
        Token indexed token,
        uint128 amount,
        uint128 ethReceived
    );

    /**
     * @notice triggered when the market price multiplier is updated
     */
    event MarketPriceMultiplyUpdated(
        uint32 prevMarketPriceMultiply,
        uint32 newMarketPriceMultiply
    );

    /**
     * @notice triggered when the price decay halflife is updated
     */
    event PriceDecayHalfLifeUpdated(
        uint32 prevPriceDecayHalfLife,
        uint32 newPriceDecayHalfLife
    );

    /**
     * @notice returns the market price multiplier
     */
    function marketPriceMultiply() external view returns (uint32);

    /**
     * @notice returns the price decay half-life according to the exp decay formula
     */
    function priceDecayHalfLife() external view returns (uint32);

    /**
     * @notice returns true if trading is enabled for token
     */
    function tradingEnabled(Token token) external view returns (bool);

    /**
     * @notice returns the expected trade output (tokens received) given an eth amount sent for a token
     */
    function expectedTradeReturn(Token token, uint128 ethAmount) external view returns (uint128 tokenAmount);

    /**
     * @notice returns the expected trade input (how much eth to send) given an token amount received
     */
    function expectedTradeInput(Token token, uint128 tokenAmount) external view returns (uint128 ethAmount);

    /**
     * @notice returns the current token price
     */
    function tokenPrice(Token token) external view returns (Price memory price);
    
    /**
     * @notice trades *amount* of token for ETH based on the current token price (trade by source amount)
     */
    function trade(Token token, uint128 amount) external payable;
}
