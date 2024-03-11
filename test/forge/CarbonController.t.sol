// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";

import { Order, TradeAction } from "../../contracts/carbon/Strategies.sol";

import { InvalidAddress } from "../../contracts/utility/Utils.sol";
import { OnlyProxyDelegate } from "../../contracts/utility/OnlyProxyDelegate.sol";

import { TestCarbonController } from "../../contracts/helpers/TestCarbonController.sol";

import { Token } from "../../contracts/token/Token.sol";

contract CarbonControllerTest is TestFixture {
    using Address for address payable;

    uint16 private constant CONTROLLER_TYPE = 1;
    uint32 private constant TRADING_FEE_PPM = 2000;

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
    }

    /**
     * @dev construction tests
     */

    function testShouldBeInitializedProperly() public {
        uint256 version = carbonController.version();
        assertEq(version, 2);

        bytes32 adminRole = keccak256("ROLE_ADMIN");
        bytes32 feesManagerRole = keccak256("ROLE_FEES_MANAGER");
        assertEq(adminRole, carbonController.roleAdmin());
        assertEq(feesManagerRole, carbonController.roleFeesManager());

        assertEq(admin, carbonController.getRoleMember(adminRole, 0));

        assertEq(1, carbonController.getRoleMemberCount(adminRole));
        assertEq(0, carbonController.getRoleMemberCount(feesManagerRole));

        assertEq(CONTROLLER_TYPE, carbonController.controllerType());
        assertEq(TRADING_FEE_PPM, carbonController.tradingFeePPM());
    }

    function testShouldRevertWhenAttemptingToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        carbonController.initialize();
    }

    /**
     * @dev other
     */

    /// @dev test should revert when querying accumulated fees with an invalid address
    function testShouldRevertWhenQueryingAccumulatedFeesWithAnInvalidAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        carbonController.accumulatedFees(Token.wrap(address(0)));
    }

    /**
     * @dev unknown delegator
     */

    /// @dev test should revert when an unknown delegator tries creating a pair
    function testShouldRevertWhenAnUnknownDelegatorTriesCreatingAPair() public {
        TestCarbonController controller = deployCarbonController(voucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        controller.createPair(Token.wrap(address(0)), Token.wrap(address(0)));
    }

    /// @dev test should revert when an unknown delegator tries creating a strategy
    function testShouldRevertWhenAnUnknownDelegatorTriesCreatingAStrategy() public {
        TestCarbonController controller = deployCarbonController(voucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        Order memory order = Order({ y: 0, z: 0, A: 0, B: 0 });
        Order[2] memory orders = [order, order];
        controller.createStrategy(Token.wrap(address(0)), Token.wrap(address(0)), orders);
    }

    /// @dev test should revert when an unknown delegator tries updating a strategy
    function testShouldRevertWhenAnUnknownDelegatorTriesUpdatingAStrategy() public {
        TestCarbonController controller = deployCarbonController(voucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        Order memory order = Order({ y: 0, z: 0, A: 0, B: 0 });
        Order[2] memory orders = [order, order];
        controller.updateStrategy(1, orders, orders);
    }

    /// @dev test should revert when an unknown delegator tries deleting a strategy
    function testShouldRevertWhenAnUnknownDelegatorTriesDeletingAStrategy() public {
        TestCarbonController controller = deployCarbonController(voucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        controller.deleteStrategy(1);
    }

    /// @dev test should revert when an unknown delegator tries trading by source amount
    function testShouldRevertWhenAnUnknownDelegatorTriesTradingBySourceAmount() public {
        TestCarbonController controller = deployCarbonController(voucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = TradeAction({ strategyId: 1, amount: 1 });
        controller.tradeBySourceAmount(Token.wrap(address(0)), Token.wrap(address(0)), tradeActions, 1, 1);
    }

    /// @dev test should revert when an unknown delegator tries trading by target amount
    function testShouldRevertWhenAnUnknownDelegatorTriesTradingByTargetAmount() public {
        TestCarbonController controller = deployCarbonController(voucher);
        vm.expectRevert(OnlyProxyDelegate.UnknownDelegator.selector);
        TradeAction[] memory tradeActions = new TradeAction[](1);
        tradeActions[0] = TradeAction({ strategyId: 1, amount: 1 });
        controller.tradeByTargetAmount(Token.wrap(address(0)), Token.wrap(address(0)), tradeActions, 1, 1);
    }
}
