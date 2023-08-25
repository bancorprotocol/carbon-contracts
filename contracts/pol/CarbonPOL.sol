// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { IStaticOracle } from "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";

import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { ICarbonPOL } from "./interfaces/ICarbonPOL.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token } from "../token/Token.sol";
import { Utils } from "../utility/Utils.sol";
import { MathEx } from "../utility/MathEx.sol";
import { MAX_GAP, PPM_RESOLUTION, PPB_RESOLUTION } from "../utility/Constants.sol";

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint value) external returns (bool);

    function withdraw(uint) external;
}

/**
 * @notice CarbonPOL contract
 */
contract CarbonPOL is ICarbonPOL, Upgradeable, ReentrancyGuardUpgradeable, Utils {
    using Address for address payable;

    // twap period for oracle verification
    uint32 private immutable _twapPeriod;

    ISwapRouter private immutable _uniswapV3Router;
    IUniswapV3Factory private immutable _uniswapV3Factory;
    IStaticOracle private immutable _uniswapV3Oracle;

    // WETH9 contract
    Token private immutable _weth;

    // block at which the contract was deployed
    uint256 private immutable _deploymentBlock;

    // rewards percentage
    uint32 private _rewardsPPM;

    // max slippage percentage
    uint32 private _maxSlippagePPM;

    // max tradeable ppb (parts per billion) per block
    uint32 private _maxTradeablePPBPerBlock;

    // mapping indicating the last block a token was traded in
    mapping(Token token => uint256 block) private _lastTradedBlock;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 2] private __gap;

    /**
     * @dev used to set immutable state variables and initialize the implementation
     */
    constructor(
        ISwapRouter uniswapV3Router,
        IUniswapV3Factory uniswapV3Factory,
        IStaticOracle uniswapV3Oracle,
        Token weth,
        uint32 twapPeriod
    )
        validAddress(address(uniswapV3Router))
        validAddress(address(uniswapV3Factory))
        validAddress(address(uniswapV3Oracle))
        validAddress(Token.unwrap(weth))
        validPeriod(twapPeriod)
    {
        _uniswapV3Router = uniswapV3Router;
        _uniswapV3Factory = uniswapV3Factory;
        _uniswapV3Oracle = uniswapV3Oracle;
        _weth = weth;
        _twapPeriod = twapPeriod;
        _deploymentBlock = block.number;

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
        _setRewardsPPM(2000);
        // 1% tradeable per day (equal to 1389 ppb per block, given 7200 blocks per day)
        _setMaxTradeablePPB(1389);
        // max slippage set to 0.3% initially
        _setMaxSlippagePPM(3000);
    }

    /**
     * @dev authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @dev perform various validations for the token array
     */
    modifier validateTokens(Token[] calldata tokens, uint24[] calldata poolFees) {
        _validateTokens(tokens, poolFees);
        _;
    }

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 1;
    }

    /**
     * @notice sets the rewards ppm
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setRewardsPPM(uint32 newRewardsPPM) external onlyAdmin validFee(newRewardsPPM) {
        _setRewardsPPM(newRewardsPPM);
    }

    /**
     * @notice sets the max slippage ppm
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMaxSlippagePPM(uint32 newMaxSlippagePPM) external onlyAdmin validFee(newMaxSlippagePPM) {
        _setMaxSlippagePPM(newMaxSlippagePPM);
    }

    /**
     * @notice sets the max tradeable ppb
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setMaxTradeablePPB(uint32 newMaxTradeablePPB) external onlyAdmin validPPBValue(newMaxTradeablePPB) {
        _setMaxTradeablePPB(newMaxTradeablePPB);
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function rewardsPPM() external view returns (uint32) {
        return _rewardsPPM;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function maxSlippagePPM() external view returns (uint32) {
        return _maxSlippagePPM;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function maxTradeablePPB() external view returns (uint32) {
        return _maxTradeablePPBPerBlock;
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function lastTradedBlock(Token token) external view returns (uint256) {
        return _lastTradedBlock[token];
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function maxTradeableAmount(Token token) external view returns (uint256) {
        uint256 balance = token.balanceOf(address(this));
        return _maxTradeableAmount(token, balance);
    }

    /**
     * @inheritdoc ICarbonPOL
     */
    function tradeTokens(
        Token[] calldata tokens,
        uint24[] calldata poolFees
    ) external nonReentrant validateTokens(tokens, poolFees) {
        uint256 len = tokens.length;

        // cache rewardsPPM to save gas
        uint32 rewardsPercentage = _rewardsPPM;
        // initialize trade and reward amount arrays
        uint256[] memory tradeAmounts = new uint256[](len);
        uint256[] memory rewardAmounts = new uint256[](len);
        uint256 totalWethAmountOut;

        // trade tokens for wETH using Uniswap V3
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            uint256 amountOut;
            (tradeAmounts[i], rewardAmounts[i], amountOut) = _convertTokenAndAllocateRewards(
                tokens[i],
                poolFees[i],
                rewardsPercentage
            );
            totalWethAmountOut += amountOut;
        }

        // convert the wETH accumulated to ETH
        uint256 wethBalance = _weth.balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(Token.unwrap(_weth)).withdraw(wethBalance);
        }

        // emit event
        emit TokensTraded(msg.sender, tokens, poolFees, tradeAmounts, rewardAmounts, totalWethAmountOut);
    }

    /**
     * @dev trades token for wETH on Uniswap V3, and transfers token reward to user
     */
    function _convertTokenAndAllocateRewards(
        Token token,
        uint24 poolFee,
        uint32 rewardsPercentage
    ) private returns (uint256 tradeAmount, uint256 rewardAmount, uint256 wethReceived) {
        // if pool doesn't exist skip token
        if (!_poolExists(token, _weth, poolFee)) {
            return (0, 0, 0);
        }
        // get token balance
        uint256 balance = token.balanceOf(address(this));
        // get trade amount for token
        tradeAmount = _maxTradeableAmount(token, balance);
        // if trade amount is zero skip token
        if (tradeAmount == 0) {
            return (0, 0, 0);
        }
        // get reward amount for token
        rewardAmount = MathEx.mulDivF(tradeAmount, rewardsPercentage, PPM_RESOLUTION);
        unchecked {
            // safe because tradeAmount >= rewardAmount
            tradeAmount -= rewardAmount;
        }

        // convert token to wETH using Uniswap V3
        wethReceived = _convertTokenToETH(token, poolFee, tradeAmount);
        // transfer reward to caller
        // @note here token can't be native - we revert in `validateTokens` if it is
        token.safeTransfer(msg.sender, rewardAmount);
    }

    /**
     * @dev trades *tradeAmount* of a token for wETH in a Uni V3 pool with *poolFee* fee 
     */
    function _convertTokenToETH(Token token, uint24 poolFee, uint256 tradeAmount) private returns (uint256 amountOut) {
        // set the last trade block to the current one
        _updateLastTradedBlock(token);

        // approve token for trading on Uniswap V3
        _setAllowance(token, tradeAmount);

        // get twap for pool
        uint24[] memory queryFees = new uint24[](1);
        queryFees[0] = poolFee;
        (uint256 quoteAmount, ) = _uniswapV3Oracle.quoteSpecificFeeTiersWithTimePeriod(
            uint128(tradeAmount),
            Token.unwrap(token),
            Token.unwrap(_weth),
            queryFees,
            _twapPeriod
        );

        // min output amount is = `twap quoted amount` - `slippage`
        uint256 minOutputAmount = quoteAmount - MathEx.mulDivF(quoteAmount, _maxSlippagePPM, PPM_RESOLUTION);

        // build the trade params
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: Token.unwrap(token),
            tokenOut: Token.unwrap(_weth),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tradeAmount,
            amountOutMinimum: minOutputAmount,
            sqrtPriceLimitX96: uint160(0)
        });

        // perform the trade
        return _uniswapV3Router.exactInputSingle(params);
    }

    /**
     * @dev helper function to check whether a given pool exists in Uni V3
     */
    function _poolExists(Token token0, Token token1, uint24 poolFee) private view returns (bool) {
        return _uniswapV3Factory.getPool(Token.unwrap(token0), Token.unwrap(token1), poolFee) != address(0);
    }

    /**
     * @dev helper function to calculate the max tradeable amount given a token and the trade amount
     * @dev max tradeable amount increases with each block and gets reset at each trade for a token
     */
    function _maxTradeableAmount(Token token, uint256 tradeAmount) private view returns (uint256) {
        uint256 lastBlockTraded = _lastTradedBlock[token];
        // if first trade for a token, check how many blocks have been mined since deployment
        uint256 lastBlock = lastBlockTraded == 0 ? _deploymentBlock : lastBlockTraded;
        uint256 blocksMined = block.number - lastBlock;
        uint256 maxPPBTradeable = _maxTradeablePPBPerBlock * blocksMined;
        // max tradeable is capped at 100% of tradeAmount
        if (maxPPBTradeable > PPB_RESOLUTION) {
            maxPPBTradeable = PPB_RESOLUTION;
        }
        return MathEx.mulDivF(tradeAmount, maxPPBTradeable, PPB_RESOLUTION);
    }

    /**
     * @dev sets the last traded block for a token to the current block
     */
    function _updateLastTradedBlock(Token token) private {
        _lastTradedBlock[token] = block.number;
    }

    function _setRewardsPPM(uint32 newRewardsPPM) private {
        uint32 prevRewardsPPM = _rewardsPPM;

        // return if the rewards percentage PPM is the same
        if (prevRewardsPPM == newRewardsPPM) {
            return;
        }

        _rewardsPPM = newRewardsPPM;

        emit RewardsUpdated({ prevRewardsPPM: prevRewardsPPM, newRewardsPPM: newRewardsPPM });
    }

    function _setMaxTradeablePPB(uint32 newMaxTradeablePPB) private {
        uint32 prevMaxTradeablePPB = _maxTradeablePPBPerBlock;

        // return if the max tradeable PPB is the same
        if (prevMaxTradeablePPB == newMaxTradeablePPB) {
            return;
        }

        _maxTradeablePPBPerBlock = newMaxTradeablePPB;

        emit MaxTradeableUpdated({ prevMaxTradeablePPB: prevMaxTradeablePPB, newMaxTradeablePPB: newMaxTradeablePPB });
    }

    function _setMaxSlippagePPM(uint32 newMaxSlippagePPM) private {
        uint32 prevMaxSlippagePPM = _maxSlippagePPM;

        // return if the max slippage PPM is the same
        if (prevMaxSlippagePPM == newMaxSlippagePPM) {
            return;
        }

        _maxSlippagePPM = newMaxSlippagePPM;

        emit MaxSlippageUpdated({ prevMaxSlippagePPM: prevMaxSlippagePPM, newMaxSlippagePPM: newMaxSlippagePPM });
    }

    /**
     * @dev set allowance to Uniswap V3 to the max amount if it's less than the input amount
     */
    function _setAllowance(Token token, uint256 inputAmount) private {
        if (token.isNative()) {
            return;
        }
        uint256 allowance = token.allowance(address(this), address(_uniswapV3Router));
        if (allowance < inputAmount) {
            // increase allowance to the max amount if allowance < inputAmount
            token.safeIncreaseAllowance(address(_uniswapV3Router), type(uint256).max - allowance);
        }
    }

    function _validateTokens(Token[] calldata tokens, uint24[] calldata poolFees) private view {
        uint len = tokens.length;
        // validate token length isn't zero
        if (len == 0) {
            revert InvalidTokenLength();
        }
        // validate token length matches pool fees length
        if (poolFees.length != len) {
            revert TokenPoolFeesLengthMismatch();
        }
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            // validate token is not the native token or weth
            if (token.isNative() || token == _weth) {
                revert InvalidToken();
            }
            // validate token has no duplicates
            for (uint256 j = uncheckedInc(i); j < len; j = uncheckedInc(j)) {
                if (token == tokens[j]) {
                    revert DuplicateToken();
                }
            }
        }
    }

    function uncheckedInc(uint256 i) private pure returns (uint256 j) {
        unchecked {
            j = i + 1;
        }
    }
}
