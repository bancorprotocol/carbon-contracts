// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { ICarbonVortex } from "./interfaces/ICarbonVortex.sol";
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
 * @dev CarbonVortex contract
 */
contract CarbonVortex is ICarbonVortex, Upgradeable, ReentrancyGuardUpgradeable, Utils {
    using Address for address payable;

    ICarbonController private immutable _carbonController;
    IBancorNetwork private immutable _bancorNetwork;
    Token private immutable _bnt;

    uint256 private _totalBurned;

    // rewards percentage
    uint256 private _rewardsPPM;

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
        __CarbonVortex_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __CarbonVortex_init() internal onlyInitializing {
        __Upgradeable_init();
        __ReentrancyGuard_init();

        __CarbonVortex_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __CarbonVortex_init_unchained() internal onlyInitializing {
        setRewardsPPM(100_000);
    }

    /**
     * @dev authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 2;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function setRewardsPPM(uint256 newRewardsPPM) public onlyAdmin validFee(uint32(newRewardsPPM)) {
        uint256 prevRewardsPPM = _rewardsPPM;

        // return if the rewards percentage PPM is the same
        if (prevRewardsPPM == newRewardsPPM) {
            return;
        }

        _rewardsPPM = newRewardsPPM;

        emit RewardsUpdated({ prevRewardsPPM: prevRewardsPPM, newRewardsPPM: newRewardsPPM });
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function rewardsPPM() external view returns (uint256) {
        return _rewardsPPM;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function totalBurned() external view returns (uint256) {
        return _totalBurned;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function availableFees(Token token) external view returns (uint256) {
        return _carbonController.accumulatedFees(token) + token.balanceOf(address(this));
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function execute(Token[] calldata tokens) external nonReentrant validateTokens(tokens) {
        uint256 len = tokens.length;

        // allocate balances array for the tokens
        uint256[] memory balances = new uint256[](len);
        // allocate array for the reward amounts for caller
        uint256[] memory rewardAmounts = new uint256[](len);
        // cache rewardsPPM to save gas
        uint256 rewardsPercentage = _rewardsPPM;

        // withdraw fees, load balances and reward amounts
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            // withdraw token fees
            _carbonController.withdrawFees(tokens[i], type(uint256).max, address(this));
            // get token balance
            balances[i] = tokens[i].balanceOf(address(this));
            // get reward amount for token
            rewardAmounts[i] = MathEx.mulDivF(balances[i], rewardsPercentage, PPM_RESOLUTION);
        }

        // convert tokens to BNT
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            // skip token if no token balance or token is BNT - no need to swap in this case
            if (balances[i] == 0 || token == _bnt) {
                continue;
            }

            // get trade amount for token
            uint256 tradeAmount = balances[i] - rewardAmounts[i];

            // approve tokens for trading on Bancor Network V3
            _setAllowance(token, tradeAmount);

            uint256 val = token.isNative() ? tradeAmount : 0;

            // swap token to BNT using Bancor Network V3
            _bancorNetwork.tradeBySourceAmount{ value: val }(token, _bnt, tradeAmount, 1, block.timestamp, address(0));
        }

        // allocate rewards to caller and burn the rest
        _allocateRewards(msg.sender, tokens, rewardAmounts);
    }

    /**
     * @dev allocates the rewards to caller and burns the rest
     */
    function _allocateRewards(address sender, Token[] calldata tokens, uint256[] memory rewardAmounts) private {
        // transfer the rewards to caller
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            uint256 rewardAmount = rewardAmounts[i];
            if (rewardAmount == 0) {
                continue;
            }
            if (token.isNative()) {
                // using a regular transfer here could revert due to exceeding the 2300 gas limit
                // which is why we're using call instead (via sendValue)
                payable(sender).sendValue(rewardAmount);
            } else {
                token.safeTransfer(sender, rewardAmount);
            }
        }

        // get the burn amount
        uint256 burnAmount = _bnt.balanceOf(address(this));

        if (burnAmount > 0) {
            // add to the total burned amount
            _totalBurned += burnAmount;
            // burn the tokens
            _bnt.safeTransfer(Token.unwrap(_bnt), burnAmount);
        }

        emit FeesBurned(sender, tokens, rewardAmounts, burnAmount);
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

    /**
     * @dev perform various validations for the token array
     */
    modifier validateTokens(Token[] calldata tokens) {
        uint len = tokens.length;
        if (len == 0) {
            revert InvalidTokenLength();
        }
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            // validate token has no duplicates
            for (uint256 j = uncheckedInc(i); j < len; j = uncheckedInc(j)) {
                if (token == tokens[j]) {
                    revert DuplicateToken();
                }
            }
            // validate token can be traded on V3
            if (token != _bnt && _bancorNetwork.collectionByPool(token) == address(0)) {
                revert InvalidToken();
            }
        }
        _;
    }
}
