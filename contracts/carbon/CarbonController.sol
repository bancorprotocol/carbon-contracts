// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IMasterVault } from "../vaults/interfaces/IMasterVault.sol";
import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { Pools, Pool } from "./Pools.sol";
import { Token } from "../token/Token.sol";
import { TokenLibrary } from "../token/TokenLibrary.sol";
import { Strategies, Strategy, TradeAction, Order, Pair, TradeTokens } from "./Strategies.sol";
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

    // the master vault contract
    IMasterVault private immutable _masterVault;

    // the voucher contract
    IVoucher private immutable _voucher;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP] private __gap;

    error IdenticalAddresses();
    error UnnecessaryNativeTokenReceived();
    error InsufficientNativeTokenReceived();
    error DeadlineExpired();
    error InvalidTradeActionAmount();
    error TokensMismatch();
    error InvalidStrategyId();
    error NoIdsProvided();
    error OutDated();

    /**
     * @dev a "virtual" constructor that is only used to set immutable state variables
     */
    constructor(IMasterVault initMasterVault, IVoucher initVoucher, address proxy) OnlyProxyDelegate(proxy) {
        _validAddress(address(initMasterVault));
        _validAddress(address(initVoucher));

        _masterVault = initMasterVault;
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
    function pairs() external view returns (address[2][] memory) {
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

        Pair memory pair = Pair({ token0: token0, token1: token1 });
        return _createStrategy(_masterVault, _voucher, pair, orders, __pool, msg.sender, msg.value);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function updateStrategy(
        uint256 strategyId,
        Order[2] calldata currentOrders,
        Order[2] calldata newOrders
    ) external payable nonReentrant whenNotPaused greaterThanZero(strategyId) onlyProxyDelegate {
        Strategy memory __strategy = _strategy(strategyId);

        // only the owner of the strategy is allowed to delete it
        if (msg.sender != _voucher.ownerOf(strategyId)) {
            revert AccessDenied();
        }

        // revert if the strategy mutated since this tx was sent
        if (!_equalStrategyOrders(currentOrders, __strategy.orders)) {
            revert OutDated();
        }

        // don't allow unnecessary eth
        if (!__strategy.pair.token0.isNative() && !__strategy.pair.token1.isNative() && msg.value > 0) {
            revert UnnecessaryNativeTokenReceived();
        }

        // revert if any of the orders is invalid
        _validateOrders(newOrders);

        // perform update
        _updateStrategy(_masterVault, __strategy, newOrders, msg.sender, msg.value);
    }

    // solhint-enable var-name-mixedcase

    /**
     * @inheritdoc ICarbonController
     */
    function deleteStrategy(
        uint256 strategyId
    ) external nonReentrant whenNotPaused greaterThanZero(strategyId) onlyProxyDelegate {
        // find strategy, reverts if none
        Strategy memory __strategy = _strategy(strategyId);

        // only the owner of the strategy is allowed to delete it
        if (msg.sender != _voucher.ownerOf(strategyId)) {
            revert AccessDenied();
        }

        // find pool
        Pool memory __pool = _pool(__strategy.pair.token0, __strategy.pair.token1);

        // delete strategy
        _deleteStrategy(__strategy, _voucher, msg.sender, _masterVault, __pool);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategy(uint256 id) external view greaterThanZero(id) returns (Strategy memory) {
        return _strategy(id);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategiesByIds(uint256[] calldata ids) external view returns (Strategy[] memory) {
        if (ids.length == 0) {
            revert NoIdsProvided();
        }

        return _strategiesByIds(ids);
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
        return _strategiesByPool(__pool, startIndex, endIndex);
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
        TradeParams memory params = TradeParams({
            trader: msg.sender,
            tokens: TradeTokens({ source: sourceToken, target: targetToken }),
            tradeActions: tradeActions,
            byTargetAmount: false,
            masterVault: _masterVault,
            constraint: minReturn,
            txValue: msg.value
        });
        SourceAndTargetAmounts memory amounts = _trade(params);
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

        TradeParams memory params = TradeParams({
            trader: msg.sender,
            tokens: TradeTokens({ source: sourceToken, target: targetToken }),
            tradeActions: tradeActions,
            byTargetAmount: true,
            masterVault: _masterVault,
            constraint: maxInput,
            txValue: msg.value
        });
        SourceAndTargetAmounts memory amounts = _trade(params);
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
        TradeTokens memory tokens = TradeTokens({ source: sourceToken, target: targetToken });
        SourceAndTargetAmounts memory amounts = _tradeSourceAndTargetAmounts(tokens, tradeActions, true);
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
        TradeTokens memory tokens = TradeTokens({ source: sourceToken, target: targetToken });
        SourceAndTargetAmounts memory amounts = _tradeSourceAndTargetAmounts(tokens, tradeActions, false);
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
     * updates the owner of a strategy following a transfer in a voucher
     *
     * requirements:
     *
     * - the caller must be the voucher contract
     *
     */
    function updateStrategyOwner(
        uint256 strategyId,
        address newOwner
    ) external only(address(_voucher)) greaterThanZero(strategyId) validAddress(newOwner) {
        Strategy memory __strategy = _strategy(strategyId);
        _updateStrategyOwner(__strategy, newOwner);
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
            if (tradeActions[i].amount <= 0) {
                revert InvalidTradeActionAmount();
            }

            // validate strategyId value
            if (tradeActions[i].strategyId <= 0) {
                revert InvalidStrategyId();
            }

            // make sure strategyIds match the provided source/target tokens
            Strategy memory s = _strategy(tradeActions[i].strategyId);
            address token0 = address(s.pair.token0);
            address token1 = address(s.pair.token1);

            if (token0 != address(sourceToken) && token0 != address(targetToken)) {
                revert TokensMismatch();
            }

            if (token1 != address(sourceToken) && token1 != address(targetToken)) {
                revert TokensMismatch();
            }
        }
    }
}
