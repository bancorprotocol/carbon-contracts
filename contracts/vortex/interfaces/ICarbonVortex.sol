// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @dev CarbonVortex interface
 */
interface ICarbonVortex is IUpgradeable {
    error DuplicateToken();
    error InvalidToken();
    error InvalidTokenLength();
    error InvalidAmountLength();
    error InvalidPrice();
    error InvalidTrade();
    error TradingDisabled();
    error PairDisabled();
    error InsufficientNativeTokenSent();
    error InsufficientAmountForTrading();

    struct Price {
        uint128 sourceAmount;
        uint128 targetAmount;
    }

    struct SaleAmount {
        uint128 initial;
        uint128 current;
    }

    /**
     * @notice triggered when trading is reset for a token (dutch auction has been restarted)
     */
    event TradingReset(Token indexed token, Price price);

    /**
     * @notice triggered after a successful trade is executed
     */
    event TokenTraded(address indexed caller, Token indexed token, uint128 sourceAmount, uint128 targetAmount);

    /**
     * @dev triggered when the rewards ppm are updated
     */
    event RewardsUpdated(uint32 prevRewardsPPM, uint32 newRewardsPPM);

    /**
     * @notice triggered when pair status is updated
     */
    event PairDisabledStatusUpdated(Token indexed token, bool prevStatus, bool newStatus);

    /**
     * @notice triggered after the price updates for a token
     */
    event PriceUpdated(Token indexed token, Price price);

    /**
     * @dev triggered when tokens have been withdrawn by the admin
     */
    event FundsWithdrawn(Token[] indexed tokens, address indexed caller, address indexed target, uint256[] amounts);

    /**
     * @notice triggered when the price reset multiplier is updated
     */
    event PriceResetMultiplierUpdated(uint32 prevPriceResetMultiplier, uint32 newPriceResetMultiplier);

    /**
     * @notice Triggered when the minimum token sale amount multiplier is updated
     */
    event MinTokenSaleAmountMultiplierUpdated(uint32 prevMinTokenSaleAmountMultiplier, uint32 newMinTokenSaleAmountMultiplier);

    /**
     * @notice triggered when the price decay halflife is updated (for all tokens except the target token)
     */
    event PriceDecayHalfLifeUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the price decay halflife is updated (for the target token only)
     */
    event TargetTokenPriceDecayHalfLifeUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the price decay halflife on price reset is updated (for the target token only)
     */
    event TargetTokenPriceDecayHalfLifeOnResetUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the target token sale amount is updated
     */
    event MaxTargetTokenSaleAmountUpdated(uint128 prevTargetTokenSaleAmount, uint128 newTargetTokenSaleAmount);

    /**
     * @notice triggered when the min token sale amount is updated
     */
    event MinTokenSaleAmountUpdated(Token indexed token, uint128 prevMinTokenSaleAmount, uint128 newMinTokenSaleAmount);

    /**
     * @dev returns the rewards percentage ppm
     */
    function rewardsPPM() external view returns (uint32);
    
    /**
    * @notice returns the price reset multiplier
    */
    function priceResetMultiplier() external view returns (uint32);
    
    /**
    * @notice returns the min token sale amount multiplier
    */
    function minTokenSaleAmountMultiplier() external view returns (uint32);

    /**
     * @notice returns the price decay half-life for all tokens except the target token
     * @notice according to the exp decay formula
     */
    function priceDecayHalfLife() external view returns (uint32);

    /**
     * @notice returns the price decay half-life for the target token according to the exp decay formula
     */
    function targetTokenPriceDecayHalfLife() external view returns (uint32);

    /**
     * @notice returns the price decay half-life for the target token on reset (slow) according to the exp decay formula
     */
    function targetTokenPriceDecayHalfLifeOnReset() external view returns (uint32);

    /**
     * @dev returns the total target (if no final target token has been defined) or final target tokens collected 
     */
    function totalCollected() external view returns (uint256);

    /**
     * @notice returns the initial and current target token sale amount
     */
    function targetTokenSaleAmount() external view returns (SaleAmount memory);

    /**
     * @notice returns the min target token sale amount
     */
    function minTargetTokenSaleAmount() external view returns (uint128);

    /**
     * @notice returns the min token sale amount
     */
    function minTokenSaleAmount(Token token) external view returns (uint128);

    /**
     * @notice returns true if pair is disabled (admin-controllable)
     */
    function pairDisabled(Token token) external view returns (bool);

    /**
     * @notice returns true if trading is enabled for token (dutch auction started)
     */
    function tradingEnabled(Token token) external view returns (bool);

    /**
     * @notice returns the amount available for trading for the token
     */
    function amountAvailableForTrading(Token token) external view returns (uint128);

    /**
     * @notice returns the target amount expected given a source amount
     */
    function expectedTradeReturn(Token token, uint128 sourceAmount) external view returns (uint128);

    /**
     * @notice returns the source amount required given a target amount
     */
    function expectedTradeInput(Token token, uint128 targetAmount) external view returns (uint128);

    /**
     * @notice returns the current token price (targetToken / TKN)
     * @notice if token == targetToken, returns finalTargetToken / targetToken price
     */
    function tokenPrice(Token token) external view returns (Price memory);

    /**
     * @dev returns the total available fees for the given token
     */
    function availableTokens(Token token) external view returns (uint256);

    /**
     * @notice trades *targetToken* for *targetAmount* of *token* based on the current token price (trade by target amount)
     * @notice if token == *targetToken*, trades *finalTargetToken* for amount of *targetToken* and also
     * @notice resets the current token sale amount if it's below the min amount after a trade
     */
    function trade(Token token, uint128 targetAmount) external payable;

    /**
     * @dev withdraws the fees of the provided token from Carbon and
     * @dev enables trading for the token if not already enabled
     */
    function execute(Token[] calldata tokens) external;
}
