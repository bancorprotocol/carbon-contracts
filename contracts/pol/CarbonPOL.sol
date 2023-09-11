// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { ICarbonPOL } from "./interfaces/ICarbonPOL.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token } from "../token/Token.sol";
import { Utils } from "../utility/Utils.sol";
import { MathEx } from "../utility/MathEx.sol";
import { ExpDecayMath } from "../utility/ExpDecayMath.sol";
import { MAX_GAP, PPM_RESOLUTION } from "../utility/Constants.sol";

/**
 * @notice CarbonPOL contract
 */
contract CarbonPOL is ICarbonPOL, Upgradeable, ReentrancyGuardUpgradeable, Utils {
    using Address for address payable;
    using SafeCast for uint256;

    // initial starting price multiplier for the dutch auction
    uint32 private _marketPriceMultiply;

    // time until the price gets back to market price
    uint32 private _priceDecayHalfLife;

    // token to trading start time mapping
    mapping(Token token => uint32 tradingStartTime) private _tradingStartTimes;

    // token to initial price mapping
    mapping(Token token => Price initialPrice) private _initialPrice;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 3] private __gap;

    /**
     * @dev used to initialize the implementation
     */
    constructor() {
        // initialize implementation
        initialize();
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() public initializer {
        __CarbonPOL_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __CarbonPOL_init() internal onlyInitializing {
        __Upgradeable_init();
        __ReentrancyGuard_init();

        __CarbonPOL_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __CarbonPOL_init_unchained() internal onlyInitializing {
        // set market price multiplier to 2x
        _setMarketPriceMultiply(2);
        // set price decay half-life to 10 days
        _setPriceDecayHalfLife(10 days);
    }

    /**
     * @dev authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @dev validate token
     */
    modifier validToken(Token token) {
        _validToken(token);
        _;
    }

    /**
     * @dev validate price
     */
    modifier validPrice(Price memory price) {
        _validPrice(price);
        _;
    }

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 1;
    }

    /**
     * @notice sets the market price multiply
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMarketPriceMultiply(
        uint32 newMarketPriceMultiply
    ) external onlyAdmin greaterThanZero(newMarketPriceMultiply) {
        _setMarketPriceMultiply(newMarketPriceMultiply);
    }

    /**
     * @notice sets the price decay half-life
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setPriceDecayHalfLife(
        uint32 newPriceDecayHalfLife
    ) external onlyAdmin greaterThanZero(newPriceDecayHalfLife) {
        _setPriceDecayHalfLife(newPriceDecayHalfLife);
    }

    /**
     * @notice enable trading for a token and set the initial price
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function enableTrading(Token token, Price memory price) external onlyAdmin validPrice(price) {
        _tradingStartTimes[token] = uint32(block.timestamp);
        _initialPrice[token] = price;
        emit TradingEnabled(token, price);
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function marketPriceMultiply() external view returns (uint32) {
        return _marketPriceMultiply;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function priceDecayHalfLife() external view returns (uint32) {
        return _priceDecayHalfLife;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function tradingEnabled(Token token) external view returns (bool) {
        return _tradingEnabled(token);
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function expectedTradeReturn(Token token, uint128 ethAmount) external view validToken(token) returns (uint128) {
        Price memory currentPrice = tokenPrice(token);
        // revert if price is not valid
        _validPrice(currentPrice);
        // multiply the token amount by the eth amount / total eth amount ratio to get the actual tokens received
        uint128 tokenAmount = MathEx.mulDivF(currentPrice.tokenAmount, ethAmount, currentPrice.ethAmount).toUint128();
        // revert if not enough token balance
        if (tokenAmount > token.balanceOf(address(this))) {
            revert InsufficientTokenBalance();
        }
        return tokenAmount;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function expectedTradeInput(Token token, uint128 tokenAmount) public view validToken(token) returns (uint128) {
        // revert if not enough token balance for trade
        if (tokenAmount > token.balanceOf(address(this))) {
            revert InsufficientTokenBalance();
        }
        Price memory currentPrice = tokenPrice(token);
        // revert if current price is not valid
        _validPrice(currentPrice);
        // multiply the eth amount by the token amount / total token amount ratio to get the actual eth to send
        return MathEx.mulDivF(currentPrice.ethAmount, tokenAmount, currentPrice.tokenAmount).toUint128();
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function tokenPrice(Token token) public view returns (Price memory) {
        // cache trading start time to save gas
        uint32 tradingStartTime = _tradingStartTimes[token];
        // revert if trading hasn't been enabled for a token
        if (tradingStartTime == 0) {
            revert TradingDisabled();
        }
        // get initial price as set by enableTrading
        Price memory price = _initialPrice[token];
        // calculate the actual price by multiplying the eth amount by the factor
        price.ethAmount *= _marketPriceMultiply;
        // get time elapsed since trading was enabled
        uint32 timeElapsed = uint32(block.timestamp) - tradingStartTime;
        // get the current price by adjusting the eth amount with the exp decay formula
        price.ethAmount = ExpDecayMath.calcExpDecay(price.ethAmount, timeElapsed, _priceDecayHalfLife).toUint128();
        // return the price
        return price;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function trade(
        Token token,
        uint128 amount
    ) external payable nonReentrant validToken(token) greaterThanZero(amount) {
        uint128 ethRequired = expectedTradeInput(token, amount);
        // revert if trade requires 0 eth
        if (ethRequired == 0) {
            revert InvalidTrade();
        }
        // check enough eth has been sent for the trade
        if (msg.value < ethRequired) {
            revert InsufficientNativeTokenSent();
        }
        // transfer the tokens to caller
        token.safeTransfer(msg.sender, amount);

        // refund any excess eth to caller
        if (msg.value > ethRequired) {
            payable(msg.sender).sendValue(msg.value - ethRequired);
        }

        // emit event
        emit TokenTraded(msg.sender, token, amount, ethRequired);
    }

    /**
     * @dev set market price multiply helper
     */
    function _setMarketPriceMultiply(uint32 newMarketPriceMultiply) private {
        uint32 prevMarketPriceMultiply = _marketPriceMultiply;

        // return if the market price multiply is the same
        if (prevMarketPriceMultiply == newMarketPriceMultiply) {
            return;
        }

        _marketPriceMultiply = newMarketPriceMultiply;

        emit MarketPriceMultiplyUpdated(prevMarketPriceMultiply, newMarketPriceMultiply);
    }

    /**
     * @dev set price decay half-life helper
     */
    function _setPriceDecayHalfLife(uint32 newPriceDecayHalfLife) private {
        uint32 prevPriceDecayHalfLife = _priceDecayHalfLife;

        // return if the price decay half-life is the same
        if (prevPriceDecayHalfLife == newPriceDecayHalfLife) {
            return;
        }

        _priceDecayHalfLife = newPriceDecayHalfLife;

        emit PriceDecayHalfLifeUpdated(prevPriceDecayHalfLife, newPriceDecayHalfLife);
    }

    /**
     * @dev validate token helper
     */
    function _validToken(Token token) private view {
        // validate token is not the native token
        if (token.isNative()) {
            revert InvalidToken();
        }
        // validate trading is enabled for token
        if (!_tradingEnabled(token)) {
            revert TradingDisabled();
        }
    }

    /**
     * @dev validate token helper
     */
    function _validPrice(Price memory price) private pure {
        if (price.tokenAmount == 0 || price.ethAmount == 0) {
            revert InvalidPrice();
        }
    }

    /**
     * @dev return true if trading is enabled for token
     */
    function _tradingEnabled(Token token) private view returns (bool) {
        return _tradingStartTimes[token] != 0;
    }
}
