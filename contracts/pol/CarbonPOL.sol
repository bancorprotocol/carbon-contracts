// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { ICarbonPOL } from "./interfaces/ICarbonPOL.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token, NATIVE_TOKEN } from "../token/Token.sol";
import { Utils } from "../utility/Utils.sol";
import { MathEx } from "../utility/MathEx.sol";
import { ExpDecayMath } from "../utility/ExpDecayMath.sol";
import { MAX_GAP } from "../utility/Constants.sol";

/**
 * @notice CarbonPOL contract
 */
contract CarbonPOL is ICarbonPOL, Upgradeable, ReentrancyGuardUpgradeable, Utils {
    using Address for address payable;
    using SafeCast for uint256;

    // bnt token address
    Token private immutable _bnt;

    // initial starting price multiplier for the dutch auction
    uint32 private _marketPriceMultiply;

    // time until the price gets back to market price
    uint32 private _priceDecayHalfLife;

    // token to trading start time mapping
    mapping(Token token => uint32 tradingStartTime) private _tradingStartTimes;

    // token to initial price mapping
    mapping(Token token => Price initialPrice) private _initialPrice;

    // initial and current eth sale amount - for ETH->BNT trades
    EthSaleAmount private _ethSaleAmount;

    // min eth sale amount - resets the current eth sale amount if below this amount after a trade
    uint128 private _minEthSaleAmount;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 5] private __gap;

    /**
     * @dev used to initialize the implementation
     */
    constructor(Token initBnt) {
        _validAddress(Token.unwrap(initBnt));
        _bnt = initBnt;
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
        // set initial eth sale amount to 100 eth
        _setEthSaleAmount(100 ether);
        // set min eth sale amount to 10 eth
        _setMinEthSaleAmount(10 ether);
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
        return 2;
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
     * @notice sets the eth sale amount
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setEthSaleAmount(uint128 newEthSaleAmount) external onlyAdmin greaterThanZero(newEthSaleAmount) {
        _setEthSaleAmount(newEthSaleAmount);
    }

    /**
     * @notice sets the min eth sale amount
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMinEthSaleAmount(uint128 newMinEthSaleAmount) external onlyAdmin greaterThanZero(newMinEthSaleAmount) {
        _setMinEthSaleAmount(newMinEthSaleAmount);
    }

    /**
     * @notice enable trading for TKN->ETH and set the initial price
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     * - can only enable trading for non-native tokens
     */
    function enableTrading(Token token, Price memory price) external onlyAdmin validPrice(price) {
        if (token == NATIVE_TOKEN) {
            revert InvalidToken();
        }
        _tradingStartTimes[token] = uint32(block.timestamp);
        _initialPrice[token] = price;
        emit TradingEnabled(token, price);
    }

    /**
     * @notice enable trading for ETH->BNT and set the initial price
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function enableTradingETH(Price memory price) external onlyAdmin validPrice(price) {
        _tradingStartTimes[NATIVE_TOKEN] = uint32(block.timestamp);
        _initialPrice[NATIVE_TOKEN] = price;
        _ethSaleAmount.current = Math.min(address(this).balance, _ethSaleAmount.initial).toUint128();
        emit TradingEnabled(NATIVE_TOKEN, price);
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
    function ethSaleAmount() external view returns (EthSaleAmount memory) {
        return _ethSaleAmount;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function minEthSaleAmount() external view returns (uint128) {
        return _minEthSaleAmount;
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
    function amountAvailableForTrading(Token token) external view returns (uint128) {
        return _amountAvailableForTrading(token);
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function expectedTradeReturn(Token token, uint128 tradeInput) external view validToken(token) returns (uint128) {
        Price memory currentPrice = tokenPrice(token);
        // revert if price is not valid
        _validPrice(currentPrice);
        // calculate the trade return based on the current price and token
        uint128 tradeReturn = MathEx
            .mulDivF(currentPrice.targetAmount, tradeInput, currentPrice.sourceAmount)
            .toUint128();
        // revert if not enough amount available for trade
        if (tradeReturn > _amountAvailableForTrading(token)) {
            revert InsufficientAmountForTrading();
        }
        return tradeReturn;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function expectedTradeInput(Token token, uint128 tokenAmount) public view validToken(token) returns (uint128) {
        // revert if not enough amount available for trade
        if (tokenAmount > _amountAvailableForTrading(token)) {
            revert InsufficientAmountForTrading();
        }
        Price memory currentPrice = tokenPrice(token);
        // revert if current price is not valid
        _validPrice(currentPrice);
        // calculate the trade input based on the current price
        return MathEx.mulDivF(currentPrice.sourceAmount, tokenAmount, currentPrice.targetAmount).toUint128();
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
        // get time elapsed since trading was enabled
        uint32 timeElapsed = uint32(block.timestamp) - tradingStartTime;
        // get initial price as set by enableTrading
        Price memory price = _initialPrice[token];
        // calculate the actual price by multiplying the amount by the factor
        price.sourceAmount *= _marketPriceMultiply;
        // get the current price by adjusting the amount with the exp decay formula
        price.sourceAmount = ExpDecayMath
            .calcExpDecay(price.sourceAmount, timeElapsed, _priceDecayHalfLife)
            .toUint128();
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
        uint128 inputAmount;
        if (token == NATIVE_TOKEN) {
            inputAmount = _sellETHForBNT(amount);
        } else {
            inputAmount = _sellTokenForETH(token, amount);
        }
        emit TokenTraded(msg.sender, token, amount, inputAmount);
    }

    function _sellTokenForETH(Token token, uint128 amount) private returns (uint128) {
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

        return ethRequired;
    }

    function _sellETHForBNT(uint128 amount) private returns (uint128) {
        uint128 bntRequired = expectedTradeInput(NATIVE_TOKEN, amount);
        // revert if trade requires 0 bnt
        if (bntRequired == 0) {
            revert InvalidTrade();
        }
        // transfer the tokens from the user to the bnt address (burn them directly)
        _bnt.safeTransferFrom(msg.sender, Token.unwrap(_bnt), bntRequired);

        // transfer the eth to the user
        payable(msg.sender).sendValue(amount);

        // update the available eth sale amount
        _ethSaleAmount.current -= amount;

        // check if remaining eth sale amount is below the min eth sale amount
        if (_ethSaleAmount.current < _minEthSaleAmount) {
            // top up the eth sale amount
            _ethSaleAmount.current = Math.min(address(this).balance, _ethSaleAmount.initial).toUint128();
            // reset the price to double the current one
            Price memory price = tokenPrice(NATIVE_TOKEN);
            _initialPrice[NATIVE_TOKEN] = price;
            _tradingStartTimes[NATIVE_TOKEN] = uint32(block.timestamp);
            // emit price updated event
            emit PriceUpdated(NATIVE_TOKEN, price);
        }

        return bntRequired;
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
     * @dev set eth sale amount helper
     */
    function _setEthSaleAmount(uint128 newEthSaleAmount) private {
        uint128 prevEthSaleAmount = _ethSaleAmount.initial;

        // return if the eth sale amount is the same
        if (prevEthSaleAmount == newEthSaleAmount) {
            return;
        }

        _ethSaleAmount.initial = newEthSaleAmount;

        // check if the new sale amount is below the current available eth sale amount
        if (newEthSaleAmount < _ethSaleAmount.current) {
            _ethSaleAmount.current = Math.min(address(this).balance, _ethSaleAmount.initial).toUint128();
        }

        emit EthSaleAmountUpdated(prevEthSaleAmount, newEthSaleAmount);
    }

    /**
     * @dev set min eth sale amount helper
     */
    function _setMinEthSaleAmount(uint128 newMinEthSaleAmount) private {
        uint128 prevMinEthSaleAmount = _minEthSaleAmount;

        // return if the min eth sale amount is the same
        if (prevMinEthSaleAmount == newMinEthSaleAmount) {
            return;
        }

        _minEthSaleAmount = newMinEthSaleAmount;

        emit MinEthSaleAmountUpdated(prevMinEthSaleAmount, newMinEthSaleAmount);
    }

    /**
     * @dev returns the token amount available for trading
     */
    function _amountAvailableForTrading(Token token) private view returns (uint128) {
        if (token == NATIVE_TOKEN) {
            return _ethSaleAmount.current;
        } else {
            return uint128(token.balanceOf(address(this)));
        }
    }

    /**
     * @dev validate token helper
     */
    function _validToken(Token token) private view {
        // validate trading is enabled for token
        if (!_tradingEnabled(token)) {
            revert TradingDisabled();
        }
    }

    /**
     * @dev validate token helper
     */
    function _validPrice(Price memory price) private pure {
        if (price.sourceAmount == 0 || price.targetAmount == 0) {
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
