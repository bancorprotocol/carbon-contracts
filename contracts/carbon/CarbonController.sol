// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { Pools, Pool } from "./Pools.sol";
import { Token } from "../token/Token.sol";
import { TokenLibrary } from "../token/TokenLibrary.sol";
import { Strategies, Strategy, TradeAction, Order, TradeTokens } from "./Strategies.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { IVoucher } from "../voucher/interfaces/IVoucher.sol";
import { ICarbonController } from "./interfaces/ICarbonController.sol";
import { Utils, AccessDenied } from "../utility/Utils.sol";
import { OnlyProxyDelegate } from "../utility/OnlyProxyDelegate.sol";
import { MAX_GAP } from "../utility/Constants.sol";

/**
 * @dev Carbon Contrller contract
 */
contract CarbonController is
    ICarbonController,
    Pools,
    Strategies,
    Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OnlyProxyDelegate,
    Utils
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using TokenLibrary for Token;

    // the emergency manager role is required to pause/unpause
    bytes32 private constant ROLE_EMERGENCY_STOPPER = keccak256("ROLE_EMERGENCY_STOPPER");

    uint16 private constant CONTROLLER_TYPE = 1;

    // the voucher contract
    IVoucher private immutable _voucher;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP] private __gap;

    error IdenticalAddresses();
    error UnnecessaryNativeTokenReceived();
    error InsufficientNativeTokenReceived();
    error DeadlineExpired();
    error InvalidTradeActionAmount();
    error NoIdsProvided();

    /**
     * @dev a "virtual" constructor that is only used to set immutable state variables
     */
    constructor(IVoucher initVoucher, address proxy) OnlyProxyDelegate(proxy) {
        _validAddress(address(initVoucher));

        _voucher = initVoucher;
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() external initializer {
        __CarbonController_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __CarbonController_init() internal onlyInitializing {
        __Upgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Strategies_init();
        __Pools_init();

        __CarbonController_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __CarbonController_init_unchained() internal onlyInitializing {
        // set up administrative roles
        _setRoleAdmin(ROLE_EMERGENCY_STOPPER, ROLE_ADMIN);
    }

    // solhint-enable func-name-mixedcase

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 2;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function controllerType() external view virtual returns (uint16) {
        return CONTROLLER_TYPE;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function tradingFeePPM() external view returns (uint32) {
        return _currentTradingFeePPM();
    }

    /**
     * @dev sets the trading fee (in units of PPM)
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setTradingFeePPM(uint32 newTradingFeePPM) external onlyAdmin validFee(newTradingFeePPM) {
        _setTradingFeePPM(newTradingFeePPM);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function createPool(
        Token token0,
        Token token1
    ) external nonReentrant whenNotPaused onlyProxyDelegate returns (Pool memory) {
        _validateInputTokens(token0, token1);
        return _createPool(token0, token1);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function pairs() external view returns (Token[2][] memory) {
        return _pairs();
    }

    /**
     * @inheritdoc ICarbonController
     */
    function pool(Token token0, Token token1) external view returns (Pool memory) {
        _validateInputTokens(token0, token1);
        return _pool(token0, token1);
    }

    // solhint-disable var-name-mixedcase

    /**
     * @inheritdoc ICarbonController
     */
    function createStrategy(
        Token token0,
        Token token1,
        Order[2] calldata orders
    ) external payable nonReentrant whenNotPaused onlyProxyDelegate returns (uint256) {
        _validateInputTokens(token0, token1);

        // don't allow unnecessary eth
        if (!token0.isNative() && !token1.isNative() && msg.value > 0) {
            revert UnnecessaryNativeTokenReceived();
        }

        // revert if any of the orders is invalid
        _validateOrders(orders);

        // create the pool if it does not exist
        Pool memory __pool;
        if (!_poolExists(token0, token1)) {
            __pool = _createPool(token0, token1);
        } else {
            __pool = _pool(token0, token1);
        }

        Token[2] memory tokens = [token0, token1];
        return _createStrategy(_voucher, tokens, orders, __pool, msg.sender, msg.value);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function updateStrategy(
        uint256 strategyId,
        Order[2] calldata currentOrders,
        Order[2] calldata newOrders
    ) external payable nonReentrant whenNotPaused onlyProxyDelegate {
        Pool memory __pool = _poolById(_poolIdbyStrategyId(strategyId));

        // only the owner of the strategy is allowed to delete it
        if (msg.sender != _voucher.ownerOf(strategyId)) {
            revert AccessDenied();
        }

        // don't allow unnecessary eth
        if (!__pool.tokens[0].isNative() && !__pool.tokens[1].isNative() && msg.value > 0) {
            revert UnnecessaryNativeTokenReceived();
        }

        // revert if any of the orders is invalid
        _validateOrders(newOrders);

        // perform update
        _updateStrategy(strategyId, __pool, currentOrders, newOrders, msg.value, msg.sender);
    }

    // solhint-enable var-name-mixedcase

    /**
     * @inheritdoc ICarbonController
     */
    function deleteStrategy(uint256 strategyId) external nonReentrant whenNotPaused onlyProxyDelegate {
        // find strategy, reverts if none
        Pool memory __pool = _poolById(_poolIdbyStrategyId(strategyId));
        Strategy memory __strategy = _strategy(strategyId, _voucher, __pool);

        // only the owner of the strategy is allowed to delete it
        if (msg.sender != _voucher.ownerOf(strategyId)) {
            revert AccessDenied();
        }

        // delete strategy
        _deleteStrategy(__strategy, _voucher, __pool);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategy(uint256 id) external view returns (Strategy memory) {
        Pool memory __pool = _poolById(_poolIdbyStrategyId(id));
        return _strategy(id, _voucher, __pool);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategiesByPool(
        Token token0,
        Token token1,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (Strategy[] memory) {
        _validateInputTokens(token0, token1);

        Pool memory __pool = _pool(token0, token1);
        return _strategiesByPool(__pool, startIndex, endIndex, _voucher);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategiesByPoolCount(Token token0, Token token1) external view returns (uint256) {
        _validateInputTokens(token0, token1);

        Pool memory __pool = _pool(token0, token1);
        return _strategiesByPoolCount(__pool);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function tradeBySourceAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions,
        uint256 deadline,
        uint128 minReturn
    ) external payable nonReentrant whenNotPaused onlyProxyDelegate returns (uint128) {
        _validateTradeParams(sourceToken, targetToken, deadline, msg.value, minReturn, tradeActions);
        Pool memory _pool = _pool(sourceToken, targetToken);
        TradeParams memory params = TradeParams({
            trader: msg.sender,
            tokens: TradeTokens({ source: sourceToken, target: targetToken }),
            byTargetAmount: false,
            constraint: minReturn,
            txValue: msg.value,
            pool: _pool
        });
        SourceAndTargetAmounts memory amounts = _trade(tradeActions, params);
        return amounts.targetAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function tradeByTargetAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions,
        uint256 deadline,
        uint128 maxInput
    ) external payable nonReentrant whenNotPaused onlyProxyDelegate returns (uint128) {
        _validateTradeParams(sourceToken, targetToken, deadline, msg.value, maxInput, tradeActions);

        if (sourceToken.isNative()) {
            // tx's value should at least match the maxInput
            if (msg.value < maxInput) {
                revert InsufficientNativeTokenReceived();
            }
        }

        Pool memory _pool = _pool(sourceToken, targetToken);
        TradeParams memory params = TradeParams({
            trader: msg.sender,
            tokens: TradeTokens({ source: sourceToken, target: targetToken }),
            byTargetAmount: true,
            constraint: maxInput,
            txValue: msg.value,
            pool: _pool
        });
        SourceAndTargetAmounts memory amounts = _trade(tradeActions, params);
        return amounts.sourceAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function tradeSourceAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint128) {
        _validateInputTokens(sourceToken, targetToken);
        Pool memory __pool = _pool(sourceToken, targetToken);
        TradeTokens memory tokens = TradeTokens({ source: sourceToken, target: targetToken });
        SourceAndTargetAmounts memory amounts = _tradeSourceAndTargetAmounts(tokens, tradeActions, __pool, true);
        return amounts.sourceAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function tradeTargetAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint128) {
        _validateInputTokens(sourceToken, targetToken);
        Pool memory __pool = _pool(sourceToken, targetToken);
        TradeTokens memory tokens = TradeTokens({ source: sourceToken, target: targetToken });
        SourceAndTargetAmounts memory amounts = _tradeSourceAndTargetAmounts(tokens, tradeActions, __pool, false);
        return amounts.targetAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function accumulatedFees(address token) external view returns (uint256) {
        _validAddress(token);
        return _getAccumulatedFees(token);
    }

    /**
     * @dev pauses the CarbonController
     *
     * requirements:
     *
     * - the caller must have the ROLE_EMERGENCY_STOPPER privilege
     */
    function pause() external onlyRoleMember(ROLE_EMERGENCY_STOPPER) {
        _pause();
    }

    /**
     * @dev resumes the CarbonController
     *
     * requirements:
     *
     * - the caller must have the ROLE_EMERGENCY_STOPPER privilege
     */
    function unpause() external onlyRoleMember(ROLE_EMERGENCY_STOPPER) {
        _unpause();
    }

    /**
     * @dev returns the emergency stopper role
     */
    function roleEmergencyStopper() external pure returns (bytes32) {
        return ROLE_EMERGENCY_STOPPER;
    }

    /**
     * @dev validates both tokens are valid addresses and unique
     */
    function _validateInputTokens(Token token0, Token token1) private pure {
        _validAddress(address(token0));
        _validAddress(address(token1));

        if (token0 == token1) {
            revert IdenticalAddresses();
        }
    }

    /**
     * performs all necessary valdations on the trade parameters
     */
    function _validateTradeParams(
        Token sourceToken,
        Token targetToken,
        uint256 deadline,
        uint256 value,
        uint128 constraint,
        TradeAction[] calldata tradeActions
    ) private view {
        // revert if deadline has passed
        if (deadline < block.timestamp) {
            revert DeadlineExpired();
        }

        // validate minReturn / maxInput
        _greaterThanZero(constraint);

        // make sure source and target tokens are valid
        _validateInputTokens(sourceToken, targetToken);

        // there shouldn't be any native token sent unless the source token is the native token
        if (!sourceToken.isNative() && value > 0) {
            revert UnnecessaryNativeTokenReceived();
        }

        // validate tradeActions
        for (uint256 i = 0; i < tradeActions.length; i++) {
            // make sure all tradeActions are provided with a positive amount
            if (tradeActions[i].amount == 0) {
                revert InvalidTradeActionAmount();
            }
        }
    }
}
