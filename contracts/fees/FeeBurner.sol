// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IFeeBurner } from "./interfaces/IFeeBurner.sol";
import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { ICarbonController } from "../carbon/interfaces/ICarbonController.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token } from "../token/Token.sol";
import { Utils } from "../utility/Utils.sol";
import { MathEx } from "../utility/MathEx.sol";
import { MAX_GAP, PPM_RESOLUTION } from "../utility/Constants.sol";

interface IBancorNetwork {
    function collectionByPool(Token pool) external view returns (address);

    function tradeBySourceAmount(
        Token sourceToken,
        Token targetToken,
        uint256 sourceAmount,
        uint256 minReturnAmount,
        uint256 deadline,
        address beneficiary
    ) external payable returns (uint256);
}

/**
 * @dev FeeBurner contract
 */
contract FeeBurner is IFeeBurner, Upgradeable, ReentrancyGuardUpgradeable, Utils {
    ICarbonController private immutable _carbonController;
    IBancorNetwork private immutable _bancorNetwork;
    Token private immutable _bnt;

    uint256 private _totalBurnt;

    // rewards percentage and max amount
    Rewards private _rewards;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 2] private __gap;

    /**
     * @dev a "virtual" constructor that is only used to set immutable state variables
     */
    constructor(
        Token bnt,
        ICarbonController carbonController,
        IBancorNetwork bancorNetwork
    ) validAddress(address(carbonController)) validAddress(Token.unwrap(bnt)) validAddress(address(bancorNetwork)) {
        _carbonController = carbonController;
        _bancorNetwork = bancorNetwork;
        _bnt = bnt;
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() external initializer {
        __FeeBurner_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __FeeBurner_init() internal onlyInitializing {
        __Upgradeable_init();
        __ReentrancyGuard_init();

        __FeeBurner_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __FeeBurner_init_unchained() internal onlyInitializing {
        setRewards(Rewards({ percentagePPM: 100_000, maxAmount: 100 * 1e18 }));
    }

    /**
     * @dev authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 1;
    }

    /**
     * @inheritdoc IFeeBurner
     */
    function setRewards(
        Rewards memory newRewards
    ) public onlyAdmin validFee(newRewards.percentagePPM) greaterThanZero(newRewards.maxAmount) {
        uint32 prevPercentagePPM = _rewards.percentagePPM;
        uint224 prevMaxAmount = _rewards.maxAmount;

        // return if the rewards are the same
        if (prevPercentagePPM == newRewards.percentagePPM && prevMaxAmount == newRewards.maxAmount) {
            return;
        }

        _rewards = newRewards;

        emit RewardsUpdated({
            prevPercentagePPM: prevPercentagePPM,
            newPercentagePPM: newRewards.percentagePPM,
            prevMaxAmount: prevMaxAmount,
            newMaxAmount: newRewards.maxAmount
        });
    }

    /**
     * @inheritdoc IFeeBurner
     */
    function rewards() external view returns (Rewards memory) {
        return _rewards;
    }

    /**
     * @inheritdoc IFeeBurner
     */
    function totalBurnt() external view returns (uint256) {
        return _totalBurnt;
    }

    /**
     * @inheritdoc IFeeBurner
     */
    function execute(Token[] calldata tokens) external nonReentrant {
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            // validate the token can be traded on V3
            if (tokens[i] != _bnt && _bancorNetwork.collectionByPool(tokens[i]) == address(0)) {
                revert InvalidToken();
            }
        }

        // withdraw tokens and convert them to BNT
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            // withdraw token fees
            uint256 fees = _carbonController.withdrawFees(tokens[i], type(uint256).max, address(this));
            // skip token if no fees have been accumulated
            if (fees == 0) {
                continue;
            }

            // check if token is BNT - we don't need to swap in this case
            if (tokens[i] == _bnt) {
                continue;
            }

            // approve tokens for trading on Bancor Network V3
            _setAllowance(tokens[i], fees);

            uint256 val = tokens[i].isNative() ? fees : 0;

            // swap tokens using Bancor Network V3
            _bancorNetwork.tradeBySourceAmount{ value: val }(tokens[i], _bnt, fees, 1, block.timestamp, address(0));
        }

        // allocate rewards to caller and burn the rest
        _allocateRewards();
    }

    /**
     * @dev allocates the rewards to msg.sender and burns the rest
     */
    function _allocateRewards() private {
        // get the total amount
        uint256 totalAmount = _bnt.balanceOf(address(this));

        // load reward amounts in memory
        Rewards memory rewardAmounts = _rewards;

        // calculate the rewards to send to the caller
        uint256 rewardAmount = MathEx.mulDivF(totalAmount, rewardAmounts.percentagePPM, PPM_RESOLUTION);

        // limit the rewards by the defined limit
        if (rewardAmount > rewardAmounts.maxAmount) {
            rewardAmount = rewardAmounts.maxAmount;
        }

        // calculate the burn amount
        uint256 burnAmount = totalAmount - rewardAmount;

        // add to the total burnt amount
        if (burnAmount > 0) {
            _totalBurnt += burnAmount;
        }

        // burn the tokens
        _bnt.safeTransfer(Token.unwrap(_bnt), burnAmount);

        // transfer the rewards to msg.sender
        _bnt.safeTransfer(msg.sender, rewardAmount);

        emit FeesBurnt(msg.sender, burnAmount, rewardAmount);
    }

    /**
     * @dev set allowance to Bancor Network V3 to the max amount if it's less than the input amount
     */
    function _setAllowance(Token token, uint256 inputAmount) private {
        if (token.isNative()) {
            return;
        }
        uint256 allowance = token.allowance(address(this), address(_bancorNetwork));
        if (allowance < inputAmount) {
            // increase allowance to the max amount if allowance < inputAmount
            token.safeIncreaseAllowance(address(_bancorNetwork), type(uint256).max - allowance);
        }
    }

    function uncheckedInc(uint256 i) private pure returns (uint256 j) {
        unchecked {
            j = i + 1;
        }
    }
}
