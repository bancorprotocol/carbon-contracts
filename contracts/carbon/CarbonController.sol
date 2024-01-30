// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { Pairs, Pair } from "./Pairs.sol";
import { Token } from "../token/Token.sol";
import { Strategies, Strategy, TradeAction, Order, TradeTokens } from "./Strategies.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { IVoucher } from "../voucher/interfaces/IVoucher.sol";
import { ICarbonController } from "./interfaces/ICarbonController.sol";
import { Utils, AccessDenied } from "../utility/Utils.sol";
import { OnlyProxyDelegate } from "../utility/OnlyProxyDelegate.sol";
import { MAX_GAP } from "../utility/Constants.sol";

/**
 * @dev Carbon Controller contract
 */
contract CarbonController is
    ICarbonController,
    Pairs,
    Strategies,
    Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OnlyProxyDelegate,
    Utils
{
    // the emergency manager role is required to pause/unpause
    bytes32 private constant ROLE_EMERGENCY_STOPPER = keccak256("ROLE_EMERGENCY_STOPPER");

    // the fees manager role is required to withdraw fees
    bytes32 private constant ROLE_FEES_MANAGER = keccak256("ROLE_FEES_MANAGER");

    uint16 private constant CONTROLLER_TYPE = 1;

    // the voucher contract
    IVoucher private immutable _voucher;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP] private __gap;

    error IdenticalAddresses();
    error UnnecessaryNativeTokenReceived();
    error InsufficientNativeTokenReceived();
    error DeadlineExpired();

    /**
     * @dev used to set immutable state variables and initialize the implementation
     */
    constructor(IVoucher initVoucher, address proxy) OnlyProxyDelegate(proxy) {
        _validAddress(address(initVoucher));

        _voucher = initVoucher;
        initialize();
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() public initializer {
        __CarbonController_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __CarbonController_init() internal onlyInitializing {
        __Pairs_init();
        __Strategies_init();
        __Upgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        __CarbonController_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __CarbonController_init_unchained() internal onlyInitializing {
        // set up administrative roles
        _setRoleAdmin(ROLE_EMERGENCY_STOPPER, ROLE_ADMIN);
        _setRoleAdmin(ROLE_FEES_MANAGER, ROLE_ADMIN);
    }

    // solhint-enable func-name-mixedcase

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure virtual override(IVersioned, Upgradeable) returns (uint16) {
        return 2;
    }

    /**
     * @dev returns the emergency stopper role
     */
    function roleEmergencyStopper() external pure returns (bytes32) {
        return ROLE_EMERGENCY_STOPPER;
    }

    /**
     * @dev returns the fees manager role
     */
    function roleFeesManager() external pure returns (bytes32) {
        return ROLE_FEES_MANAGER;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function controllerType() external pure virtual returns (uint16) {
        return CONTROLLER_TYPE;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function tradingFeePPM() external view returns (uint32) {
        return _tradingFeePPM;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function pairTradingFeePPM(Token token0, Token token1) external view returns (uint32) {
        Pair memory _pair = _pair(token0, token1);
        return _getPairTradingFeePPM(_pair.id);
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
     * @dev sets the custom trading fee for a given pair (in units of PPM)
     *
     * requirements:
     *
     * - the caller must be the admin of the contract
     */
    function setPairTradingFeePPM(
        Token token0,
        Token token1,
        uint32 newPairTradingFeePPM
    ) external onlyAdmin validFee(newPairTradingFeePPM) {
        Pair memory _pair = _pair(token0, token1);
        _setPairTradingFeePPM(_pair, newPairTradingFeePPM);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function createPair(
        Token token0,
        Token token1
    ) external nonReentrant whenNotPaused onlyProxyDelegate returns (Pair memory) {
        _validateInputTokens(token0, token1);
        return _createPair(token0, token1);
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
    function pair(Token token0, Token token1) external view returns (Pair memory) {
        _validateInputTokens(token0, token1);
        return _pair(token0, token1);
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
        if (msg.value > 0 && !token0.isNative() && !token1.isNative()) {
            revert UnnecessaryNativeTokenReceived();
        }

        // revert if any of the orders is invalid
        _validateOrders(orders);

        // create the pair if it does not exist
        Pair memory strategyPair;
        if (!_pairExists(token0, token1)) {
            strategyPair = _createPair(token0, token1);
        } else {
            strategyPair = _pair(token0, token1);
        }

        Token[2] memory tokens = [token0, token1];
        return _createStrategy(_voucher, tokens, orders, strategyPair, msg.sender, msg.value);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function updateStrategy(
        uint256 strategyId,
        Order[2] calldata currentOrders,
        Order[2] calldata newOrders
    ) external payable nonReentrant whenNotPaused onlyProxyDelegate {
        Pair memory strategyPair = _pairById(_pairIdByStrategyId(strategyId));

        // only the owner of the strategy is allowed to delete it
        if (msg.sender != _voucher.ownerOf(strategyId)) {
            revert AccessDenied();
        }

        // don't allow unnecessary eth
        if (msg.value > 0 && !strategyPair.tokens[0].isNative() && !strategyPair.tokens[1].isNative()) {
            revert UnnecessaryNativeTokenReceived();
        }

        // revert if any of the orders is invalid
        _validateOrders(newOrders);

        // perform update
        _updateStrategy(strategyId, currentOrders, newOrders, strategyPair, msg.sender, msg.value);
    }

    // solhint-enable var-name-mixedcase

    /**
     * @inheritdoc ICarbonController
     */
    function deleteStrategy(uint256 strategyId) external nonReentrant whenNotPaused onlyProxyDelegate {
        // find strategy, reverts if none
        Pair memory strategyPair = _pairById(_pairIdByStrategyId(strategyId));

        // only the owner of the strategy is allowed to delete it
        if (msg.sender != _voucher.ownerOf(strategyId)) {
            revert AccessDenied();
        }

        // delete strategy
        _deleteStrategy(strategyId, _voucher, strategyPair);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategy(uint256 id) external view returns (Strategy memory) {
        Pair memory strategyPair = _pairById(_pairIdByStrategyId(id));
        return _strategy(id, _voucher, strategyPair);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategiesByPair(
        Token token0,
        Token token1,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (Strategy[] memory) {
        _validateInputTokens(token0, token1);

        Pair memory strategyPair = _pair(token0, token1);
        return _strategiesByPair(strategyPair, startIndex, endIndex, _voucher);
    }

    /**
     * @inheritdoc ICarbonController
     */
    function strategiesByPairCount(Token token0, Token token1) external view returns (uint256) {
        _validateInputTokens(token0, token1);

        Pair memory strategyPair = _pair(token0, token1);
        return _strategiesByPairCount(strategyPair);
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
        _validateTradeParams(sourceToken, targetToken, deadline, msg.value, minReturn);
        Pair memory _pair = _pair(sourceToken, targetToken);
        TradeParams memory params = TradeParams({
            trader: msg.sender,
            tokens: TradeTokens({ source: sourceToken, target: targetToken }),
            byTargetAmount: false,
            constraint: minReturn,
            txValue: msg.value,
            pair: _pair,
            sourceAmount: 0,
            targetAmount: 0
        });
        _trade(tradeActions, params);
        return params.targetAmount;
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
        _validateTradeParams(sourceToken, targetToken, deadline, msg.value, maxInput);

        if (sourceToken.isNative()) {
            // tx's value should at least match the maxInput
            if (msg.value < maxInput) {
                revert InsufficientNativeTokenReceived();
            }
        }

        Pair memory _pair = _pair(sourceToken, targetToken);
        TradeParams memory params = TradeParams({
            trader: msg.sender,
            tokens: TradeTokens({ source: sourceToken, target: targetToken }),
            byTargetAmount: true,
            constraint: maxInput,
            txValue: msg.value,
            pair: _pair,
            sourceAmount: 0,
            targetAmount: 0
        });
        _trade(tradeActions, params);
        return params.sourceAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function calculateTradeSourceAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint128) {
        _validateInputTokens(sourceToken, targetToken);
        Pair memory strategyPair = _pair(sourceToken, targetToken);
        TradeTokens memory tokens = TradeTokens({ source: sourceToken, target: targetToken });
        SourceAndTargetAmounts memory amounts = _tradeSourceAndTargetAmounts(tokens, tradeActions, strategyPair, true);
        return amounts.sourceAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function calculateTradeTargetAmount(
        Token sourceToken,
        Token targetToken,
        TradeAction[] calldata tradeActions
    ) external view returns (uint128) {
        _validateInputTokens(sourceToken, targetToken);
        Pair memory strategyPair = _pair(sourceToken, targetToken);
        TradeTokens memory tokens = TradeTokens({ source: sourceToken, target: targetToken });
        SourceAndTargetAmounts memory amounts = _tradeSourceAndTargetAmounts(tokens, tradeActions, strategyPair, false);
        return amounts.targetAmount;
    }

    /**
     * @inheritdoc ICarbonController
     */
    function accumulatedFees(Token token) external view validAddress(Token.unwrap(token)) returns (uint256) {
        return _accumulatedFees[token];
    }

    /**
     * @inheritdoc ICarbonController
     */
    function withdrawFees(
        Token token,
        uint256 amount,
        address recipient
    )
        external
        whenNotPaused
        onlyRoleMember(ROLE_FEES_MANAGER)
        validAddress(recipient)
        validAddress(Token.unwrap(token))
        greaterThanZero(amount)
        nonReentrant
        returns (uint256)
    {
        return _withdrawFees(msg.sender, amount, token, recipient);
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
     * @dev validates both tokens are valid addresses and unique
     */
    function _validateInputTokens(
        Token token0,
        Token token1
    ) private pure validAddress(Token.unwrap(token0)) validAddress(Token.unwrap(token1)) {
        if (token0 == token1) {
            revert IdenticalAddresses();
        }
    }

    /**
     * performs all necessary validations on the trade parameters
     */
    function _validateTradeParams(
        Token sourceToken,
        Token targetToken,
        uint256 deadline,
        uint256 value,
        uint128 constraint
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
        if (value > 0 && !sourceToken.isNative()) {
            revert UnnecessaryNativeTokenReceived();
        }
    }
}
