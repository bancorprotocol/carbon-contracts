// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 4] private __gap;

    /**
     * @dev used to initialize the implementation
     */
    constructor(Token bntInit) {
        _bnt = bntInit;
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
        _ethSaleAmount.current = _ethSaleAmount.initial;
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
    function ethSaleAmount() external view returns (uint128) {
        return _ethSaleAmount.initial;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function currentEthSaleAmount() external view returns (uint128) {
        return _ethSaleAmount.current;
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
        // check available balance
        uint128 amountToCheck = token == NATIVE_TOKEN ? ethAmount : tokenAmount;
        // revert if not enough token balance
        if (amountToCheck > token.balanceOf(address(this))) {
            revert InsufficientTokenBalance();
        }
        return tokenAmount;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function expectedTradeInput(Token token, uint128 tokenAmount) public view validToken(token) returns (uint128) {
        // revert if not enough token balance for trade
        if (token != NATIVE_TOKEN && tokenAmount > token.balanceOf(address(this))) {
            revert InsufficientTokenBalance();
        }
        Price memory currentPrice = tokenPrice(token);
        // revert if current price is not valid
        _validPrice(currentPrice);
        // multiply the eth amount by the token amount / total token amount ratio to get the actual eth to send
        uint128 ethAmount = MathEx.mulDivF(currentPrice.ethAmount, tokenAmount, currentPrice.tokenAmount).toUint128();
        // check if enough token balance
        if (token == NATIVE_TOKEN && ethAmount > token.balanceOf(address(this))) {
            revert InsufficientTokenBalance();
        }
        return ethAmount;
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
        // get the price token or eth amount for applying the exp decay formula to
        uint128 amount = token == NATIVE_TOKEN ? price.tokenAmount : price.ethAmount;
        // calculate the actual price by multiplying the amount by the factor
        amount *= _marketPriceMultiply;
        // get the current price by adjusting the amount with the exp decay formula
        amount = ExpDecayMath.calcExpDecay(amount, timeElapsed, _priceDecayHalfLife).toUint128();
        // update the price
        if (token == NATIVE_TOKEN) {
            price.tokenAmount = amount;
        } else {
            price.ethAmount = amount;
        }
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
        uint128 ethAmount;
        if (token == NATIVE_TOKEN) {
            ethAmount = _sellETHForBNT(amount);
        } else {
            ethAmount = _sellTokenForETH(token, amount);
        }
        emit TokenTraded(msg.sender, token, amount, ethAmount);
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
        uint128 ethAmountRequired = expectedTradeInput(NATIVE_TOKEN, amount);
        if (_ethSaleAmount.current < ethAmountRequired) {
            revert InsufficientEthForSale();
        }
        // revert if trade requires 0 eth
        if (ethAmountRequired == 0) {
            revert InvalidTrade();
        }
        // transfer the tokens from the user
        _bnt.safeTransferFrom(msg.sender, address(this), amount);

        // transfer the eth to the user
        payable(msg.sender).sendValue(ethAmountRequired);

        // update the available eth sale amount
        _ethSaleAmount.current -= ethAmountRequired;

        // check if below 10% of the initial eth sale amount
        if (_ethSaleAmount.current < _ethSaleAmount.initial / 10) {
            // top up the eth sale amount
            _ethSaleAmount.current = _ethSaleAmount.initial;
            // reset the price to double the current one
            Price memory price = tokenPrice(NATIVE_TOKEN);
            price.tokenAmount *= _marketPriceMultiply;
            _initialPrice[NATIVE_TOKEN] = price;
            // emit price updated event
            emit PriceUpdated(NATIVE_TOKEN, price);
        }

        return ethAmountRequired;
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
            _ethSaleAmount.current = newEthSaleAmount;
        }

        emit EthSaleAmountUpdated(prevEthSaleAmount, newEthSaleAmount);
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
