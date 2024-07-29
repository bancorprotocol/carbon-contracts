// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";

import { GradientOrder, TradeAction, Price, GradientCurve, GradientCurveTypes } from "../../contracts/carbon/GradientStrategies.sol";

import { InvalidAddress } from "../../contracts/utility/Utils.sol";
import { OnlyProxyDelegate } from "../../contracts/utility/OnlyProxyDelegate.sol";

import { TestGradientController } from "../../contracts/helpers/TestGradientController.sol";

import { Token } from "../../contracts/token/Token.sol";

contract GradientControllerTest is TestFixture {
    using Address for address payable;

    uint16 private constant CONTROLLER_TYPE = 2;
    uint32 private constant TRADING_FEE_PPM = 4000;

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Gradient Controller and Voucher
        setupGradientController();
    }

    /**
     * @dev construction tests
     */

    function testShouldBeInitializedProperly() public view {
        uint256 version = gradientController.version();
        assertEq(version, 2);

        bytes32 adminRole = keccak256("ROLE_ADMIN");
        bytes32 feesManagerRole = keccak256("ROLE_FEES_MANAGER");
        assertEq(adminRole, gradientController.roleAdmin());
        assertEq(feesManagerRole, gradientController.roleFeesManager());

        assertEq(admin, gradientController.getRoleMember(adminRole, 0));

        assertEq(1, gradientController.getRoleMemberCount(adminRole));
        assertEq(0, gradientController.getRoleMemberCount(feesManagerRole));

        assertEq(CONTROLLER_TYPE, gradientController.controllerType());
        assertEq(TRADING_FEE_PPM, gradientController.tradingFeePPM());
    }

    function testShouldRevertWhenAttemptingToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        gradientController.initialize();
    }

    /**
     * @dev other
     */

    /// @dev test should revert when querying accumulated fees with an invalid address
    function testShouldRevertWhenQueryingAccumulatedFeesWithAnInvalidAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        gradientController.accumulatedFees(Token.wrap(address(0)));
    }

    /**
     * @dev unknown delegator
     */

    /// @dev test should revert when an unknown delegator tries creating a pair
    function testShouldRevertWhenAnUnknownDelegatorTriesCreatingAPair() public {
        TestGradientController controller = deployGradientController(gradientVoucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        controller.createPair(Token.wrap(address(0)), Token.wrap(address(0)));
    }

    /// @dev test should revert when an unknown delegator tries creating a strategy
    function testShouldRevertWhenAnUnknownDelegatorTriesCreatingAStrategy() public {
        TestGradientController controller = deployGradientController(gradientVoucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        // initialize gradient order
        Price memory initialPrice = Price({ sourceAmount: 0, targetAmount: 0 });
        Price memory endPrice = Price({ sourceAmount: 0, targetAmount: 0 });
        GradientCurve memory curve = GradientCurve({
            curveType: GradientCurveTypes.LINEAR,
            increaseAmount: 0,
            increaseInterval: 0,
            halflife: 0,
            isDutchAuction: false
        });
        GradientOrder memory order = GradientOrder({
            initialPrice: initialPrice,
            endPrice: endPrice,
            sourceAmount: 0,
            targetAmount: 0,
            tradingStartTime: 0,
            expiry: 0,
            tokensInverted: false,
            curve: curve
        });
        controller.createStrategy(Token.wrap(address(0)), Token.wrap(address(0)), order);
    }

    /// @dev test should revert when an unknown delegator tries updating a strategy
    function testShouldRevertWhenAnUnknownDelegatorTriesUpdatingAStrategy() public {
        TestGradientController controller = deployGradientController(gradientVoucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        // initialize gradient order
        Price memory initialPrice = Price({ sourceAmount: 0, targetAmount: 0 });
        Price memory endPrice = Price({ sourceAmount: 0, targetAmount: 0 });
        GradientCurve memory curve = GradientCurve({
            curveType: GradientCurveTypes.LINEAR,
            increaseAmount: 0,
            increaseInterval: 0,
            halflife: 0,
            isDutchAuction: false
        });
        GradientOrder memory order = GradientOrder({
            initialPrice: initialPrice,
            endPrice: endPrice,
            sourceAmount: 0,
            targetAmount: 0,
            tradingStartTime: 0,
            expiry: 0,
            tokensInverted: false,
            curve: curve
        });
        controller.updateStrategy(1, order, order);
    }

    /// @dev test should revert when an unknown delegator tries deleting a strategy
    function testShouldRevertWhenAnUnknownDelegatorTriesDeletingAStrategy() public {
        TestGradientController controller = deployGradientController(gradientVoucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        controller.deleteStrategy(1);
    }

    /// @dev test should revert when an unknown delegator tries trading by source amount
    function testShouldRevertWhenAnUnknownDelegatorTriesTradingBySourceAmount() public {
        TestGradientController controller = deployGradientController(gradientVoucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = TradeAction({ strategyId: 1, amount: 1 });
        controller.tradeBySourceAmount(Token.wrap(address(0)), Token.wrap(address(0)), tradeActions, 1, 1);
    }

    /// @dev test should revert when an unknown delegator tries trading by target amount
    function testShouldRevertWhenAnUnknownDelegatorTriesTradingByTargetAmount() public {
        TestGradientController controller = deployGradientController(gradientVoucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = TradeAction({ strategyId: 1, amount: 1 });
        controller.tradeByTargetAmount(Token.wrap(address(0)), Token.wrap(address(0)), tradeActions, 1, 1);
    }
}
