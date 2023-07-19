// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { TestFixture } from "./TestFixture.sol";

import { Order, Strategy, Strategies } from "../../contracts/carbon/Strategies.sol";

import { AccessDenied, ZeroValue, InvalidAddress, InvalidFee, InvalidIndices } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";

import { CarbonController } from "../../contracts/carbon/CarbonController.sol";
import { Strategies } from "../../contracts/carbon/Strategies.sol";
import { Pairs } from "../../contracts/carbon/Pairs.sol";
import { TestVoucher } from "../../contracts/helpers/TestVoucher.sol";
import { TestCarbonController } from "../../contracts/helpers/TestCarbonController.sol";
import { TestERC20FeeOnTransfer } from "../../contracts/helpers/TestERC20FeeOnTransfer.sol";

import { IVoucher } from "../../contracts/voucher/interfaces/IVoucher.sol";

import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract StrategiesTest is TestFixture {
    using Address for address payable;

    // strategy update reasons
    uint8 private constant STRATEGY_UPDATE_REASON_EDIT = 0;
    uint8 private constant STRATEGY_UPDATE_REASON_TRADE = 1;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 2000;
    uint32 private constant NEW_TRADING_FEE_PPM = 300_000;

    uint256 private constant FETCH_AMOUNT = 5;

    /**
     * @dev triggered when the network fee is updated
     */
    event TradingFeePPMUpdated(uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev triggered when a strategy is created
     */
    event StrategyCreated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

    /**
     * @dev triggered when a strategy is deleted
     */
    event StrategyDeleted(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );

    /**
     * @dev triggered when a strategy is updated
     */
    event StrategyUpdated(
        uint256 indexed id,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1,
        uint8 reason
    );

    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev triggered when fees are withdrawn
     */
    event FeesWithdrawn(Token indexed token, address indexed recipient, uint256 indexed amount, address sender);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
        // Approve tokens to carbon controller
        vm.startPrank(admin);
        uint256 approveAmount = MAX_SOURCE_AMOUNT;
        token0.safeApprove(address(carbonController), approveAmount);
        token1.safeApprove(address(carbonController), approveAmount);
        token2.safeApprove(address(carbonController), approveAmount);
        vm.stopPrank();
        // Approve tokens to carbon controller
        vm.startPrank(user1);
        token0.safeApprove(address(carbonController), approveAmount);
        token1.safeApprove(address(carbonController), approveAmount);
        token2.safeApprove(address(carbonController), approveAmount);
        vm.stopPrank();
    }

    /**
     * @dev strategy creation tests
     */

    /// @dev test that the strategy creation reverts for identical token addresses
    function testStrategyCreationShouldRevertWhenTokenAddressesAreIdentical() public {
        Order memory order = generateTestOrder();
        vm.expectRevert(CarbonController.IdenticalAddresses.selector);
        carbonController.createStrategy(token0, token0, [order, order]);
    }

    /// @dev test that the strategy creation stores the information correctly
    function testStrategyCreationStoresTheInformationCorrectly(
        uint256 i0,
        uint256 i1,
        uint256 t0Amount,
        uint256 t1Amount
    ) public {
        vm.startPrank(admin);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, token1, NATIVE_TOKEN];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);
        // bound amounts from 0 to 8000000
        t0Amount = bound(t0Amount, 0, 8000000);
        t1Amount = bound(t1Amount, 0, 8000000);

        Order memory order0 = generateTestOrder(t0Amount);
        Order memory order1 = generateTestOrder(t1Amount);

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN ? t0Amount : 0;
        val = tokens[i1] == NATIVE_TOKEN ? t1Amount : val;
        carbonController.createStrategy{ value: val }(tokens[i0], tokens[i1], [order0, order1]);

        uint256 strategyId = generateStrategyId(1, 1);

        Strategy memory strategy = carbonController.strategy(strategyId);

        Strategy memory expectedStrategy = Strategy({
            id: strategyId,
            owner: admin,
            tokens: [tokens[i0], tokens[i1]],
            orders: [order0, order1]
        });

        bool structsAreEqual = compareStrategyStructs(strategy, expectedStrategy);

        assertTrue(structsAreEqual);

        vm.stopPrank();
    }

    /// @dev test that the strategy creation reverts for non valid addresses
    function testStrategyCreationRevertsForNonValidAddresses(uint256 i0, uint256 i1) public {
        vm.startPrank(admin);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, Token.wrap(address(0)), Token.wrap(address(0))];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        uint256 amount = 1000;

        Order memory order = generateTestOrder(amount);

        vm.expectRevert(InvalidAddress.selector);
        carbonController.createStrategy(tokens[i0], tokens[i1], [order, order]);
        vm.stopPrank();
    }

    /// @dev test that the strategy creation emits the StrategyCreated event
    function testStrategyCreationEmitsTheStrategyCreatedEvent() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        Order memory order = generateTestOrder(amount);

        uint256 strategyId = generateStrategyId(1, 1);

        vm.expectEmit();
        emit StrategyCreated(strategyId, admin, token0, token1, order, order);
        carbonController.createStrategy(token0, token1, [order, order]);
        vm.stopPrank();
    }

    /// @dev test that strategy creation mints a voucher token to the caller
    function testStrategyCreationMintsVoucherTokenToTheCaller() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        Order memory order = generateTestOrder(amount);
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        uint256 balance = voucher.balanceOf(admin);
        address owner = voucher.ownerOf(strategyId);

        assertEq(balance, 1);
        assertEq(owner, admin);

        vm.stopPrank();
    }

    /// @dev test that the strategy creation emits the Voucher transfer event
    function testStrategyCreationEmitsTheVoucherTransferEvent() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        Order memory order = generateTestOrder(amount);

        uint256 strategyId = generateStrategyId(1, 1);

        vm.expectEmit();
        emit Transfer(address(0), admin, strategyId);
        carbonController.createStrategy(token0, token1, [order, order]);
        vm.stopPrank();
    }

    /// @dev test that strategy creation increases strategy id
    function testStrategyCreationIncreasesStrategyId() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        Order memory order = generateTestOrder(amount);

        uint256 firstStrategyId = carbonController.createStrategy(token0, token1, [order, order]);
        uint256 secondStrategyId = carbonController.createStrategy(token0, token1, [order, order]);
        uint256 expectedStrategyId = generateStrategyId(1, 2);

        assertEq(firstStrategyId + 1, secondStrategyId);
        assertEq(secondStrategyId, expectedStrategyId);

        vm.stopPrank();
    }

    /// @dev test that the strategy creation updates caller and controller balances correctly
    function testStrategyCreationBalancesAreUpdatedCorrectly(
        uint256 i0,
        uint256 i1,
        uint256 t0Amount,
        uint256 t1Amount
    ) public {
        vm.startPrank(user1);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, token1, NATIVE_TOKEN];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);
        // bound amounts from 0 to 8000000
        t0Amount = bound(t0Amount, 0, 8000000);
        t1Amount = bound(t1Amount, 0, 8000000);

        Order memory order0 = generateTestOrder(t0Amount);
        Order memory order1 = generateTestOrder(t1Amount);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN ? t0Amount : 0;
        val = tokens[i1] == NATIVE_TOKEN ? t1Amount : val;
        carbonController.createStrategy{ value: val }(tokens[i0], tokens[i1], [order0, order1]);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // user1 balance should decrease by y amount
        assertEq(balancesAfter[0], balancesBefore[0] - t0Amount);
        assertEq(balancesAfter[1], balancesBefore[1] - t1Amount);

        // controller balance should increase by y amount
        assertEq(balancesAfter[2], balancesBefore[2] + t0Amount);
        assertEq(balancesAfter[3], balancesBefore[3] + t1Amount);

        vm.stopPrank();
    }

    /// @dev test that the strategy creation refunds any excess native token sent
    function testStrategyCreationExcessNativeTokenIsRefunded(uint256 i0, uint256 t0Amount, uint256 t1Amount) public {
        vm.startPrank(user1);
        // use two of the below tokens for the strategy
        Token[2] memory tokens = [token0, NATIVE_TOKEN];
        // pick two random numbers from 0 to 1 for the tokens
        i0 = bound(i0, 0, 1);
        uint256 i1 = i0 == 0 ? 1 : 0;
        // bound amounts from 0 to 8000000
        t0Amount = bound(t0Amount, 0, 8000000);
        t1Amount = bound(t1Amount, 0, 8000000);

        Order memory order0 = generateTestOrder(t0Amount);
        Order memory order1 = generateTestOrder(t1Amount);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN ? t0Amount : 0;
        val = tokens[i1] == NATIVE_TOKEN ? t1Amount : val;
        // send 1 eth extra
        val += 1 ether;
        carbonController.createStrategy{ value: val }(tokens[i0], tokens[i1], [order0, order1]);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // user1 balance should decrease by y amount
        assertEq(balancesAfter[0], balancesBefore[0] - t0Amount);
        assertEq(balancesAfter[1], balancesBefore[1] - t1Amount);

        // controller balance should increase by y amount
        assertEq(balancesAfter[2], balancesBefore[2] + t0Amount);
        assertEq(balancesAfter[3], balancesBefore[3] + t1Amount);

        vm.stopPrank();
    }

    function testStrategyCreationRevertsWhenUnnecessaryNativeTokenWasSent() public {
        Order memory order = generateTestOrder();
        vm.expectRevert(CarbonController.UnnecessaryNativeTokenReceived.selector);
        carbonController.createStrategy{ value: 1000 }(token0, token1, [order, order]);
    }

    function testStrategyCreationRevertsForFeeOnTransferTokens() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();

        feeOnTransferToken.safeApprove(address(carbonController), order.y * 2);

        // test revert with negative transfer fee
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.createStrategy(feeOnTransferToken, token1, [order, order]);
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.createStrategy(token0, feeOnTransferToken, [order, order]);

        // change fee side
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeSide(false);

        // test revert with positive transfer fee
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.createStrategy(feeOnTransferToken, token1, [order, order]);
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.createStrategy(token0, feeOnTransferToken, [order, order]);

        vm.stopPrank();
    }

    function testStrategyCreationRevertsWhenPaused() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleEmergencyStopper(), user2);
        vm.stopPrank();
        vm.prank(user2);
        carbonController.pause();

        Order memory order = generateTestOrder();
        vm.expectRevert("Pausable: paused");
        carbonController.createStrategy(token0, token1, [order, order]);
    }

    function testSStrategyCreationRevertsWhenCapacityIsSmallerThanLiquidity(bool order0Insufficient) public {
        vm.startPrank(user1);

        Order memory order0 = generateTestOrder();
        Order memory order1 = generateTestOrder();
        if (order0Insufficient) {
            order0.z = order0.y - 1;
        } else {
            order1.z = order1.y - 1;
        }

        vm.expectRevert(Strategies.InsufficientCapacity.selector);
        carbonController.createStrategy(token0, token1, [order0, order1]);

        vm.stopPrank();
    }

    function testStrategyCreationRevertsWhenAnyOfTheRatesAreInvalid(bool order0Invalid, bool rateA) public {
        vm.startPrank(user1);

        Order memory order0 = generateTestOrder();
        Order memory order1 = generateTestOrder();
        if (order0Invalid) {
            if (rateA) {
                order0.A = 2 ** 64 - 1;
            } else {
                order0.B = 2 ** 64 - 1;
            }
        } else {
            if (rateA) {
                order1.A = 2 ** 64 - 1;
            } else {
                order1.B = 2 ** 64 - 1;
            }
        }

        vm.expectRevert(Strategies.InvalidRate.selector);
        carbonController.createStrategy(token0, token1, [order0, order1]);

        vm.stopPrank();
    }

    function testStrategyCreationTokenSortingPersist(bool token0First) public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        uint256 strategyId;
        if (token0First) {
            strategyId = carbonController.createStrategy(token0, token1, [order, order]);
            Strategy memory strategy = carbonController.strategy(strategyId);
            assertTrue(strategy.tokens[0] == token0);
            assertTrue(strategy.tokens[1] == token1);
        } else {
            strategyId = carbonController.createStrategy(token1, token0, [order, order]);
            Strategy memory strategy = carbonController.strategy(strategyId);
            assertTrue(strategy.tokens[0] == token1);
            assertTrue(strategy.tokens[1] == token0);
        }

        vm.stopPrank();
    }

    /**
     * @dev strategy update tests
     */

    /// @dev test that the strategy update stores orders correctly
    function testStrategyUpdateStoresOrdersCorrectly(uint256 i0, uint256 i1, int64[2] memory deltas) public {
        vm.startPrank(user1);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, token1, NATIVE_TOKEN];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);
        // bound deltas from -800000 to 800000
        deltas[0] = int64(bound(deltas[0], -800000, 800000));
        deltas[1] = int64(bound(deltas[1], -800000, 800000));

        // generate order
        Order memory order = generateTestOrder();

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN || tokens[i1] == NATIVE_TOKEN ? order.y : 0;
        uint256 strategyId = carbonController.createStrategy{ value: val }(tokens[i0], tokens[i1], [order, order]);

        // create new orders
        Order memory order0 = updateOrderDelta(order, deltas[0]);
        Order memory order1 = updateOrderDelta(order, deltas[1]);

        // update strategy
        val = getValueToSend(tokens[i0], tokens[i1], deltas[0], deltas[1]);
        carbonController.updateStrategy{ value: val }(strategyId, [order, order], [order0, order1]);

        Strategy memory strategy = carbonController.strategy(strategyId);

        Strategy memory expectedStrategy = Strategy({
            id: strategyId,
            owner: user1,
            tokens: [tokens[i0], tokens[i1]],
            orders: [order0, order1]
        });

        // compare strategies
        assertTrue(compareStrategyStructs(strategy, expectedStrategy));

        vm.stopPrank();
    }

    /// @dev test that the strategy update stores orders correctly without liquidity change
    function testStrategyUpdateStoresOrderCorrectlyWithoutLiquidityChange(
        uint256[2] memory i,
        bool delta0Negative
    ) public {
        vm.startPrank(user1);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, token1, NATIVE_TOKEN];
        // pick two random numbers from 0 to 2 for the tokens and delta changes
        i[0] = bound(i[0], 0, 2);
        i[1] = bound(i[1], 0, 2);
        vm.assume(i[0] != i[1]);

        int64[2] memory deltas;
        if (delta0Negative) {
            deltas[0] = -1;
            deltas[1] = 1;
        } else {
            deltas[0] = 1;
            deltas[1] = -1;
        }

        Order memory order = generateTestOrder();

        // create strategy
        uint256 val = tokens[i[0]] == NATIVE_TOKEN || tokens[i[1]] == NATIVE_TOKEN ? order.y : 0;
        uint256 strategyId = carbonController.createStrategy{ value: val }(tokens[i[0]], tokens[i[1]], [order, order]);

        // create new orders
        Order memory order0 = updateOrderDelta(order, deltas[0]);
        Order memory order1 = updateOrderDelta(order, deltas[1]);

        // update strategy
        val = tokens[i[0]] == NATIVE_TOKEN && deltas[0] >= 0 ? abs(deltas[0]) : 0;
        val += tokens[i[1]] == NATIVE_TOKEN && deltas[1] >= 0 ? abs(deltas[1]) : 0;
        carbonController.updateStrategy{ value: val }(strategyId, [order, order], [order0, order1]);

        Strategy memory strategy = carbonController.strategy(strategyId);

        Strategy memory expectedStrategy = Strategy({
            id: strategyId,
            owner: user1,
            tokens: [tokens[i[0]], tokens[i[1]]],
            orders: [order0, order1]
        });

        // compare strategies
        assertTrue(compareStrategyStructs(strategy, expectedStrategy));

        vm.stopPrank();
    }

    /// @dev test that the strategy update updates caller and controller balances correctly
    function testStrategyUpdateBalancesAreUpdatedCorrectly(uint256 i0, uint256 i1, int64[2] memory deltas) public {
        vm.startPrank(user1);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, token1, NATIVE_TOKEN];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);
        // bound deltas from -800000 to 800000
        deltas[0] = int64(bound(deltas[0], -800000, 800000));
        deltas[1] = int64(bound(deltas[1], -800000, 800000));

        Order memory order = generateTestOrder();

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN || tokens[i1] == NATIVE_TOKEN ? order.y : 0;
        uint256 strategyId = carbonController.createStrategy{ value: val }(tokens[i0], tokens[i1], [order, order]);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // create new orders
        Order memory order0 = updateOrderDelta(order, deltas[0]);
        Order memory order1 = updateOrderDelta(order, deltas[1]);

        // update strategy
        val = getValueToSend(tokens[i0], tokens[i1], deltas[0], deltas[1]);
        carbonController.updateStrategy{ value: val }(strategyId, [order, order], [order0, order1]);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // user1 balance should decrease by delta amount and controller should increase if delta is positive
        // user1 balance should increase by delta amount and controller should decrease if delta is negative
        if (deltas[0] >= 0) {
            assertEq(balancesAfter[0], balancesBefore[0] - abs(deltas[0]));
            assertEq(balancesAfter[2], balancesBefore[2] + abs(deltas[0]));
        } else {
            assertEq(balancesAfter[0], balancesBefore[0] + abs(deltas[0]));
            assertEq(balancesAfter[2], balancesBefore[2] - abs(deltas[0]));
        }
        if (deltas[1] >= 0) {
            assertEq(balancesAfter[1], balancesBefore[1] - abs(deltas[1]));
            assertEq(balancesAfter[3], balancesBefore[3] + abs(deltas[1]));
        } else {
            assertEq(balancesAfter[1], balancesBefore[1] + abs(deltas[1]));
            assertEq(balancesAfter[3], balancesBefore[3] - abs(deltas[1]));
        }

        vm.stopPrank();
    }

    /// @dev test that the strategy update without full withdrawal refunds excess native token sent
    function testStrategyUpdateExcessNativeTokenIsRefundedWithoutFullWithdrawal(
        uint256 i0,
        int64[2] memory deltas
    ) public {
        vm.startPrank(user1);
        // use two of the below tokens for the strategy
        Token[2] memory tokens = [token0, NATIVE_TOKEN];
        // pick two random numbers from 0 to 1 for the tokens
        i0 = bound(i0, 0, 1);
        uint256 i1 = i0 == 0 ? 1 : 0;
        vm.assume(i0 != i1);
        // bound deltas from -800000 to 800000
        deltas[0] = int64(bound(deltas[0], -800000, 800000));
        deltas[1] = int64(bound(deltas[1], -800000, 800000));

        Order memory order = generateTestOrder();

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN || tokens[i1] == NATIVE_TOKEN ? order.y : 0;
        uint256 strategyId = carbonController.createStrategy{ value: val }(tokens[i0], tokens[i1], [order, order]);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // create new orders
        Order memory order0 = updateOrderDelta(order, deltas[0]);
        Order memory order1 = updateOrderDelta(order, deltas[1]);

        // update strategy
        val = getValueToSend(tokens[i0], tokens[i1], deltas[0], deltas[1]);
        // add excess native token
        val += 1 ether;
        carbonController.updateStrategy{ value: val }(strategyId, [order, order], [order0, order1]);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(carbonController)),
            tokens[i1].balanceOf(address(carbonController))
        ];

        // user1 balance should decrease by delta amount and controller should increase if delta is positive
        // user1 balance should increase by delta amount and controller should decrease if delta is negative
        if (deltas[0] >= 0) {
            assertEq(balancesAfter[0], balancesBefore[0] - abs(deltas[0]));
            assertEq(balancesAfter[2], balancesBefore[2] + abs(deltas[0]));
        } else {
            assertEq(balancesAfter[0], balancesBefore[0] + abs(deltas[0]));
            assertEq(balancesAfter[2], balancesBefore[2] - abs(deltas[0]));
        }
        if (deltas[1] >= 0) {
            assertEq(balancesAfter[1], balancesBefore[1] - abs(deltas[1]));
            assertEq(balancesAfter[3], balancesBefore[3] + abs(deltas[1]));
        } else {
            assertEq(balancesAfter[1], balancesBefore[1] + abs(deltas[1]));
            assertEq(balancesAfter[3], balancesBefore[3] - abs(deltas[1]));
        }

        vm.stopPrank();
    }

    /// @dev test that the strategy update reverts if the reference tokens are not equal to the current
    function testStrategyUpdateRevertsIfTheProvidedReferenceTokensAreNotEqualToTheCurrent(
        Order memory orderDeltas
    ) public {
        vm.startPrank(user1);
        // bound y, z delta values from 0 to 100 000
        orderDeltas.y = uint128(bound(orderDeltas.y, 0, 100000));
        orderDeltas.z = uint128(bound(orderDeltas.z, 0, 100000));
        // bound A, B delta values from 0 to 100 000
        orderDeltas.A = uint64(bound(orderDeltas.A, 0, 100000));
        orderDeltas.B = uint64(bound(orderDeltas.B, 0, 100000));

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        order.y += orderDeltas.y;
        order.z += orderDeltas.z;
        order.A += orderDeltas.A;
        order.B += orderDeltas.B;

        vm.expectRevert(Strategies.OutDated.selector);
        carbonController.updateStrategy(strategyId, [order, order], [order, order]);

        vm.stopPrank();
    }

    /// @dev test that the strategy update emits an event on edit
    function testStrategyUpdateEmitsEventOnEdit(int64[2] memory deltas) public {
        vm.startPrank(user1);

        // bound deltas from -800000 to 800000
        deltas[0] = int64(bound(deltas[0], -800000, 800000));
        deltas[1] = int64(bound(deltas[1], -800000, 800000));

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // create new orders
        Order memory order0 = updateOrderDelta(order, deltas[0]);
        Order memory order1 = updateOrderDelta(order, deltas[1]);

        vm.expectEmit();
        emit StrategyUpdated(strategyId, token0, token1, order0, order1, STRATEGY_UPDATE_REASON_EDIT);
        carbonController.updateStrategy(strategyId, [order, order], [order0, order1]);

        vm.stopPrank();
    }

    /// @dev test that the strategy update reverts when unnecessary native token was sent
    function testStrategyUpdateRevertsWhenUnnecessaryNativeTokenWasSent() public {
        vm.startPrank(user1);

        int64[2] memory deltas = [int64(-100), int64(100)];

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // create new orders
        Order memory order0 = updateOrderDelta(order, deltas[0]);
        Order memory order1 = updateOrderDelta(order, deltas[1]);

        vm.expectRevert(CarbonController.UnnecessaryNativeTokenReceived.selector);
        carbonController.updateStrategy{ value: 100 }(strategyId, [order, order], [order0, order1]);

        vm.stopPrank();
    }

    function testStrategyUpdateRevertsForFeeOnTransferTokens() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();

        feeOnTransferToken.safeApprove(address(carbonController), order.y * 2);

        // disable fee to create strategy
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeEnabled(false);

        // create strategy
        uint256 strategyId = carbonController.createStrategy(feeOnTransferToken, token1, [order, order]);

        // enable fee to test strategy update
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeEnabled(true);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        // test revert with negative transfer fee
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);

        // change fee side
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeSide(false);

        // test revert with positive transfer fee
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);
        vm.expectRevert(Strategies.BalanceMismatch.selector);
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);

        vm.stopPrank();
    }

    function testStrategyUpdateRevertsWhenPaused() public {
        vm.prank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleEmergencyStopper(), user2);
        vm.stopPrank();
        vm.prank(user2);
        carbonController.pause();

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        vm.expectRevert("Pausable: paused");
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);
    }

    function testStrategyUpdateRevertsWhenTryingToUpdateANonExistingStrategyOnAnExistingPair() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        uint256 strategyId = generateStrategyId(1, 2);

        vm.expectRevert("ERC721: invalid token ID");
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);

        vm.stopPrank();
    }

    function testStrategyUpdateRevertsWhenTryingToUpdateANonExistingStrategyOnANonExistingPair() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        uint256 strategyId = generateStrategyId(2, 3);

        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);

        vm.stopPrank();
    }

    function testStrategyUpdateRevertsWhenTheProvidedStrategyIdIsZero() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.updateStrategy(0, [order, order], [newOrder, newOrder]);

        vm.stopPrank();
    }

    function testStrategyUpdateRevertsWhenANonOwnerAttemptsToUpdateAStrategy() public {
        vm.prank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        vm.prank(user2);
        vm.expectRevert(AccessDenied.selector);
        carbonController.updateStrategy(strategyId, [order, order], [newOrder, newOrder]);
    }

    function testStrategyUpdateRevertsWhenCapacityIsSmallerThanLiquidity(bool order0Insufficient) public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        Order memory order0 = generateTestOrder();
        Order memory order1 = generateTestOrder();
        if (order0Insufficient) {
            order0.z = order0.y - 1;
        } else {
            order1.z = order1.y - 1;
        }

        vm.expectRevert(Strategies.InsufficientCapacity.selector);
        carbonController.updateStrategy(strategyId, [order, order], [order0, order1]);

        vm.stopPrank();
    }

    function testStrategyUpdateRevertsWhenAnyOfTheRatesAreInvalid(bool order0Invalid, bool rateA) public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        Order memory order0 = generateTestOrder();
        Order memory order1 = generateTestOrder();
        if (order0Invalid) {
            if (rateA) {
                order0.A = 2 ** 64 - 1;
            } else {
                order0.B = 2 ** 64 - 1;
            }
        } else {
            if (rateA) {
                order1.A = 2 ** 64 - 1;
            } else {
                order1.B = 2 ** 64 - 1;
            }
        }

        vm.expectRevert(Strategies.InvalidRate.selector);
        carbonController.updateStrategy(strategyId, [order, order], [order0, order1]);

        vm.stopPrank();
    }

    /**
     * @dev strategy deletion tests
     */

    /// @dev test that the strategy deletion burns the voucher token
    function testVoucherBurnsFollowingAStrategyDeletion() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        carbonController.deleteStrategy(strategyId);
        vm.expectRevert("ERC721: invalid token ID");
        voucher.ownerOf(strategyId);

        vm.stopPrank();
    }

    /// @dev test that the strategy deletion updates caller and controller balances correctly
    function testStrategyDeletionBalancesAreUpdatedCorrectly(uint256 amount) public {
        vm.startPrank(user1);

        // bound order amount from 0 to 800000
        amount = bound(amount, 0, 800000);

        Order memory order = generateTestOrder(amount);
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            token0.balanceOf(user1),
            token1.balanceOf(user1),
            token0.balanceOf(address(carbonController)),
            token1.balanceOf(address(carbonController))
        ];

        carbonController.deleteStrategy(strategyId);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            token0.balanceOf(user1),
            token1.balanceOf(user1),
            token0.balanceOf(address(carbonController)),
            token1.balanceOf(address(carbonController))
        ];

        // user1 balance should increase by amount
        assertEq(balancesAfter[0], balancesBefore[0] + amount);
        assertEq(balancesAfter[1], balancesBefore[1] + amount);

        // controller balance should decrease by amount
        assertEq(balancesAfter[2], balancesBefore[2] - amount);
        assertEq(balancesAfter[3], balancesBefore[3] - amount);

        vm.stopPrank();
    }

    /// @dev test that the strategy deletion clears storage
    function testStrategyDeletionClearsStorage(uint256 amount) public {
        vm.startPrank(user1);

        // bound order amount from 0 to 800000
        amount = bound(amount, 0, 800000);

        Order memory order = generateTestOrder(amount);
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // assert before deleting
        Strategy memory strategy = carbonController.strategy(strategyId);
        Strategy[] memory strategiesByPair = carbonController.strategiesByPair(token0, token1, 0, 0);

        assertEq(strategy.id, strategyId);
        assertEq(strategiesByPair[0].id, strategyId);

        // delete strategy
        carbonController.deleteStrategy(strategyId);

        // assert after deleting
        vm.expectRevert("ERC721: invalid token ID");
        carbonController.strategy(strategyId);

        strategiesByPair = carbonController.strategiesByPair(token0, token1, 0, 0);
        assertEq(strategiesByPair.length, 0);

        vm.stopPrank();
    }

    /// @dev test that the strategy deletion emits event
    function testStrategyDeletionEmitsEvent(uint256 amount) public {
        vm.startPrank(user1);

        // bound order amount from 0 to 800000
        amount = bound(amount, 0, 800000);

        Order memory order = generateTestOrder(amount);
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // delete strategy
        vm.expectEmit();
        emit StrategyDeleted(strategyId, user1, token0, token1, order, order);
        carbonController.deleteStrategy(strategyId);

        vm.stopPrank();
    }

    /// @dev test should be able to delete a strategy when first order is disabled
    function testShouldBeAbleToDeleteAStrategyWhenFirstOrderIsDisabled() public {
        vm.startPrank(user1);

        Order memory disabledOrder = generateDisabledOrder();
        Order memory secondOrder = generateTestOrder();
        uint256 strategyId = carbonController.createStrategy(token0, token1, [disabledOrder, secondOrder]);

        // delete strategy
        vm.expectEmit();
        emit StrategyDeleted(strategyId, user1, token0, token1, disabledOrder, secondOrder);
        carbonController.deleteStrategy(strategyId);

        vm.stopPrank();
    }

    /// @dev test should be able to delete a strategy when second order is disabled
    function testShouldBeAbleToDeleteAStrategyWhenSecondOrderIsDisabled() public {
        vm.startPrank(user1);

        Order memory firstOrder = generateTestOrder();
        Order memory disabledOrder = generateDisabledOrder();
        uint256 strategyId = carbonController.createStrategy(token0, token1, [firstOrder, disabledOrder]);

        // delete strategy
        vm.expectEmit();
        emit StrategyDeleted(strategyId, user1, token0, token1, firstOrder, disabledOrder);
        carbonController.deleteStrategy(strategyId);

        vm.stopPrank();
    }

    /// @dev test should be able to delete a strategy when both orders are disabled
    function testShouldBeAbleToDeleteAStrategyWhenBothOrdersAreDisabled() public {
        vm.startPrank(user1);

        Order memory order = generateDisabledOrder();
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // delete strategy
        vm.expectEmit();
        emit StrategyDeleted(strategyId, user1, token0, token1, order, order);
        carbonController.deleteStrategy(strategyId);

        vm.stopPrank();
    }

    function testStrategyDeletionRevertsWhenTheProvidedStrategyIdIsZero() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.deleteStrategy(0);

        vm.stopPrank();
    }

    function testStrategyDeletionRevertsWhenANonOwnerAttemptsToDeleteAStrategy() public {
        vm.prank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        vm.prank(user2);
        vm.expectRevert(AccessDenied.selector);
        carbonController.deleteStrategy(strategyId);
    }

    function testStrategyDeletionRevertsWhenTryingToDeleteANonExistingStrategyOnAnExistingPair() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        uint256 strategyId = generateStrategyId(1, 2);

        vm.expectRevert("ERC721: invalid token ID");
        carbonController.deleteStrategy(strategyId);

        vm.stopPrank();
    }

    function testStrategyDeletionRevertsWhenTryingToDeleteANonExistingStrategyOnANonExistingPair() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        Order memory newOrder = generateTestOrder();
        newOrder.y += 1000;

        uint256 strategyId = generateStrategyId(2, 3);

        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.deleteStrategy(strategyId);

        vm.stopPrank();
    }

    function testStrategyDeletionRevertsWhenPaused() public {
        vm.prank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleEmergencyStopper(), user2);
        vm.stopPrank();
        vm.prank(user2);
        carbonController.pause();

        vm.expectRevert("Pausable: paused");
        carbonController.deleteStrategy(strategyId);
    }

    /**
     * @dev trading fee tests
     */

    function testShouldRevertWhenANonAdminAttemptsToSetTheTradingFee() public {
        vm.prank(user2);
        vm.expectRevert(AccessDenied.selector);
        carbonController.setTradingFeePPM(NEW_TRADING_FEE_PPM);
    }

    function testShouldRevertWhenSettingTheTradingFeeToAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(InvalidFee.selector);
        carbonController.setTradingFeePPM(PPM_RESOLUTION + 1);
    }

    function testFailShouldIgnoreUpdatingToTheSameTradingFee() public {
        uint32 tradingFee = carbonController.tradingFeePPM();
        vm.prank(admin);
        vm.expectEmit();
        emit TradingFeePPMUpdated(tradingFee, tradingFee);
        carbonController.setTradingFeePPM(NEW_TRADING_FEE_PPM);
    }

    function testShouldBeAbleToSetAndUpdateTheTradingFee() public {
        uint32 tradingFee = carbonController.tradingFeePPM();
        vm.prank(admin);
        vm.expectEmit();
        emit TradingFeePPMUpdated(tradingFee, NEW_TRADING_FEE_PPM);
        carbonController.setTradingFeePPM(NEW_TRADING_FEE_PPM);

        tradingFee = carbonController.tradingFeePPM();
        assertEq(tradingFee, NEW_TRADING_FEE_PPM);
    }

    function testSetsTheDefaultOnInitialization() public {
        uint32 tradingFee = carbonController.tradingFeePPM();
        assertEq(tradingFee, DEFAULT_TRADING_FEE_PPM);
    }

    /**
     * @dev fetch by pair tests
     */

    function testFetchByPairRevertsWhenAddressesAreIdentical() public {
        vm.expectRevert(CarbonController.IdenticalAddresses.selector);
        carbonController.strategiesByPair(token0, token0, 0, 0);
    }

    function testFetchByPairRevertsWhenNoPairFoundForGivenTokens() public {
        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.strategiesByPair(token0, token1, 0, 0);
    }

    function testFetchByPairRevertsForNonValidAddresses(uint256 i0, uint256 i1) public {
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, Token.wrap(address(0)), Token.wrap(address(0))];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        vm.expectRevert(InvalidAddress.selector);
        carbonController.strategiesByPair(tokens[i0], tokens[i1], 0, 0);
    }

    function testFetchByPairFetchesTheCorrectStrategies() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId0 = carbonController.createStrategy(token0, token1, [order, order]);
        uint256 strategyId1 = carbonController.createStrategy(token0, token1, [order, order]);
        uint256 strategyId2 = carbonController.createStrategy(token0, token2, [order, order]);

        Strategy[] memory strategies = carbonController.strategiesByPair(token0, token1, 0, 0);
        assertEq(strategies.length, 2);
        assertEq(strategies[0].id, strategyId0);
        assertEq(strategies[1].id, strategyId1);
        assertEq(Token.unwrap(strategies[0].tokens[0]), Token.unwrap(token0));
        assertEq(Token.unwrap(strategies[0].tokens[1]), Token.unwrap(token1));
        assertEq(Token.unwrap(strategies[1].tokens[0]), Token.unwrap(token0));
        assertEq(Token.unwrap(strategies[1].tokens[1]), Token.unwrap(token1));

        strategies = carbonController.strategiesByPair(token0, token2, 0, 0);

        assertEq(strategies.length, 1);
        assertEq(strategies[0].id, strategyId2);
        assertEq(Token.unwrap(strategies[0].tokens[0]), Token.unwrap(token0));
        assertEq(Token.unwrap(strategies[0].tokens[1]), Token.unwrap(token2));

        vm.stopPrank();
    }

    function testFetchByPairSetsTheEndIndexToTheMaxPossibleIfProvidedWithZero() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategies
        for (uint256 i = 0; i < FETCH_AMOUNT; ++i) {
            carbonController.createStrategy(token0, token1, [order, order]);
        }

        Strategy[] memory strategies = carbonController.strategiesByPair(token0, token1, 0, 0);
        assertEq(strategies.length, FETCH_AMOUNT);

        vm.stopPrank();
    }

    function testFetchByPairSetsTheEndIndexToTheMaxPossibleIfProvidedWithAnOutOfBoundValue() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategies
        for (uint256 i = 0; i < FETCH_AMOUNT; ++i) {
            carbonController.createStrategy(token0, token1, [order, order]);
        }

        Strategy[] memory strategies = carbonController.strategiesByPair(token0, token1, 0, FETCH_AMOUNT + 100);
        assertEq(strategies.length, FETCH_AMOUNT);

        vm.stopPrank();
    }

    function testFetchByPairRevertsIfStartIndexIsGreaterThanEndIndex() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategies
        for (uint256 i = 0; i < FETCH_AMOUNT; ++i) {
            carbonController.createStrategy(token0, token1, [order, order]);
        }

        vm.expectRevert(InvalidIndices.selector);
        carbonController.strategiesByPair(token0, token1, FETCH_AMOUNT + 1, FETCH_AMOUNT);

        vm.stopPrank();
    }

    /**
     * @dev fetch by pair count tests
     */

    function testFetchByPairCountRevertsWhenAddressesAreIdentical() public {
        vm.expectRevert(CarbonController.IdenticalAddresses.selector);
        carbonController.strategiesByPairCount(token0, token0);
    }

    function testFetchByPairCountRevertsWhenNoPairFoundForGivenTokens() public {
        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.strategiesByPairCount(token0, token1);
    }

    function testFetchByPairCountRevertsForNonValidAddresses(uint256 i0, uint256 i1) public {
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, Token.wrap(address(0)), Token.wrap(address(0))];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        vm.expectRevert(InvalidAddress.selector);
        carbonController.strategiesByPairCount(tokens[i0], tokens[i1]);
    }

    function testFetchByPairCountReturnsTheCorrectCount() public {
        vm.startPrank(user1);
        Order memory order = generateTestOrder();
        // create strategies
        for (uint256 i = 0; i < FETCH_AMOUNT; ++i) {
            carbonController.createStrategy(token0, token1, [order, order]);
            carbonController.createStrategy(token0, token2, [order, order]);
        }

        uint256 result1 = carbonController.strategiesByPairCount(token0, token1);
        uint256 result2 = carbonController.strategiesByPairCount(token0, token2);
        assertEq(result1, FETCH_AMOUNT);
        assertEq(result2, FETCH_AMOUNT);

        vm.stopPrank();
    }

    /**
     * @dev fetch by a single id tests
     */

    function testFetchByASingleIdRevertsWhenFetchingANonExistingStrategyOnAnExistingPair() public {
        vm.prank(user1);
        Order memory order = generateTestOrder();
        carbonController.createStrategy(token0, token1, [order, order]);
        uint256 strategyId = generateStrategyId(1, 2);
        vm.expectRevert("ERC721: invalid token ID");
        carbonController.strategy(strategyId);
    }

    function testFetchByASingleIdRevertsWhenFetchingANonExistingStrategyOnAnNonExistingPair() public {
        uint256 strategyId = generateStrategyId(2, 3);

        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.strategy(strategyId);
    }

    function testFetchByASingleIdRevertsWhenTheProvidedStrategyIdIsZero() public {
        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        carbonController.strategy(0);
    }

    function testFetchByASingleIdReturnsTheCorrectStrategy() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        carbonController.createStrategy(token0, token1, [order, order]);
        carbonController.createStrategy(token0, token1, [order, order]);

        uint256 strategyId = generateStrategyId(1, 2);
        Strategy memory strategy = carbonController.strategy(strategyId);
        assertEq(strategy.id, strategyId);

        vm.stopPrank();
    }

    /**
     * @dev voucher tests
     */

    function testVoucherTransferUpdatesVoucherOwner() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // transfer the voucher token
        voucher.transferFrom(user1, user2, strategyId);

        // fetch tokens by owner
        uint256[] memory oldTokenIds = voucher.tokensByOwner(user1, 0, 100);
        uint256[] memory newTokenIds = voucher.tokensByOwner(user2, 0, 100);
        address newOwner = voucher.ownerOf(strategyId);

        assertEq(oldTokenIds.length, 0);
        assertEq(newTokenIds[0], strategyId);
        assertEq(newOwner, user2);

        vm.stopPrank();
    }

    function testVoucherTransferUpdatesStrategyOwner() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // transfer the voucher token
        voucher.transferFrom(user1, user2, strategyId);

        // fetch the strategy
        Strategy memory strategy = carbonController.strategy(strategyId);

        assertEq(strategy.owner, user2);

        vm.stopPrank();
    }

    function testVoucherTransferRevertsForAnInvalidStrategyId() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        // create strategy
        carbonController.createStrategy(token0, token1, [order, order]);

        uint256 strategyId = generateStrategyId(1, 2);

        // transfer the voucher token
        vm.expectRevert("ERC721: invalid token ID");
        voucher.transferFrom(user1, user2, 0);
        vm.expectRevert("ERC721: invalid token ID");
        voucher.transferFrom(user1, user2, strategyId);

        vm.stopPrank();
    }

    function testVoucherTransferRevertsForAnInvalidTargetAddress() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // transfer the voucher token
        vm.expectRevert("ERC721: transfer to the zero address");
        voucher.transferFrom(user1, address(0), strategyId);

        vm.stopPrank();
    }

    function testVoucherTransferEmitsEvent() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);

        // transfer the voucher token
        vm.expectEmit();
        emit Transfer(user1, user2, strategyId);
        voucher.transferFrom(user1, user2, strategyId);

        // fetch the strategy
        Strategy memory strategy = carbonController.strategy(strategyId);

        assertEq(strategy.owner, user2);

        vm.stopPrank();
    }

    /**
     * @dev token URI tests
     */

    function testVoucherGeneratesAGlobalURI() public {
        vm.startPrank(admin);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);
        // set base uri
        voucher.setBaseURI("ipfs://test321");
        voucher.useGlobalURI(true);

        string memory uri = voucher.tokenURI(strategyId);
        assertEq(uri, "ipfs://test321");

        vm.stopPrank();
    }

    function testVoucherGeneratesAnUniqueURI() public {
        vm.startPrank(admin);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);
        // set base uri
        voucher.setBaseURI("ipfs://test321");
        voucher.useGlobalURI(false);

        string memory expectedUri = string.concat("ipfs://test321", Strings.toString(strategyId));

        string memory uri = voucher.tokenURI(strategyId);
        assertEq(uri, expectedUri);

        vm.stopPrank();
    }

    function testVoucherGeneratesAnUniqueURIWithBaseExtension() public {
        vm.startPrank(admin);

        Order memory order = generateTestOrder();
        // create strategy
        uint256 strategyId = carbonController.createStrategy(token0, token1, [order, order]);
        // set base uri
        voucher.setBaseURI("ipfs://test321");
        voucher.setBaseExtension(".json");
        voucher.useGlobalURI(false);

        string memory expectedUri = string.concat("ipfs://test321", Strings.toString(strategyId));
        expectedUri = string.concat(expectedUri, ".json");

        string memory uri = voucher.tokenURI(strategyId);
        assertEq(uri, expectedUri);

        vm.stopPrank();
    }

    function testRevertsIfATransferOccursBeforeTheMinterRoleWasSetToCarbonController() public {
        // Deploy Voucher
        TestVoucher newVoucher = deployVoucher();
        // Deploy Carbon Controller
        TestCarbonController newCarbonController = deployCarbonController(newVoucher);

        vm.startPrank(admin);

        // Deploy new Carbon Controller to set proxy address in constructor
        address carbonControllerImpl = address(
            new TestCarbonController(IVoucher(address(voucher)), address(newCarbonController))
        );

        // Upgrade Carbon Controller to set proxy address in constructor
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(newCarbonController)), carbonControllerImpl);

        // Set Carbon Controller address
        carbonController = TestCarbonController(payable(address(newCarbonController)));

        Order memory order = generateTestOrder();
        order.y = 0;
        // create strategy
        vm.expectRevert(AccessDenied.selector);
        newCarbonController.createStrategy(token0, token1, [order, order]);

        vm.stopPrank();
    }

    function testFailSkipsTransfersOfZeroAmount() public {
        vm.startPrank(user1);

        Order memory order = generateTestOrder();
        order.y = 0;
        vm.expectEmit();
        emit Transfer(user1, address(carbonController), 0);
        carbonController.createStrategy(token0, token1, [order, order]);

        vm.stopPrank();
    }

    /**
     * @dev withdraw fees tests
     */

    function testFeeWithdrawalRevertsWhenPaused() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleEmergencyStopper(), user2);
        vm.stopPrank();
        vm.prank(user1);
        Order memory order = generateTestOrder();
        carbonController.createStrategy(token0, token1, [order, order]);
        vm.prank(user2);
        carbonController.pause();

        vm.prank(admin);
        vm.expectRevert("Pausable: paused");
        carbonController.withdrawFees(token0, 1, admin);
    }

    function testFeeWithdrawalRevertsWhenCallerIsMissingTheRequiredRole() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonController.withdrawFees(token0, 1, admin);
    }

    function testFeeWithdrawalRevertsWhenTheRecipientAddressIsInvalid() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);
        vm.expectRevert(InvalidAddress.selector);
        carbonController.withdrawFees(token0, 1, address(0));

        vm.stopPrank();
    }

    function testFeeWithdrawalRevertsWhenTheTokenAddressIsInvalid() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);
        vm.expectRevert(InvalidAddress.selector);
        carbonController.withdrawFees(Token.wrap(address(0)), 1, admin);

        vm.stopPrank();
    }

    function testFeeWithdrawalRevertsWhenTheTokenAmountIsInvalid() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);
        vm.expectRevert(ZeroValue.selector);
        carbonController.withdrawFees(token0, 0, admin);

        vm.stopPrank();
    }

    function testFeeWithdrawalEmitsEvent() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);

        uint256 withdrawAmount = 10;
        token0.safeTransfer(address(carbonController), withdrawAmount);
        carbonController.testSetAccumulatedFees(token0, withdrawAmount);
        vm.expectEmit();
        emit FeesWithdrawn(token0, admin, withdrawAmount, admin);
        carbonController.withdrawFees(token0, withdrawAmount, admin);

        vm.stopPrank();
    }

    function testFailEmitFeeWithdrawalIfAccumulatedFeeAmountIsZero() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);

        uint256 withdrawAmount = 10;
        vm.expectEmit();
        emit FeesWithdrawn(token0, admin, withdrawAmount, admin);
        carbonController.withdrawFees(token0, withdrawAmount, admin);

        vm.stopPrank();
    }

    function testFeeWithdrawalUpdatesAccumulatedFeesBalance() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);

        uint256 withdrawAmount = 10;
        token0.safeTransfer(address(carbonController), withdrawAmount);
        carbonController.withdrawFees(token0, withdrawAmount, admin);

        uint256 accumulatedFees = carbonController.testAccumulatedFees(token0);

        assertEq(accumulatedFees, 0);

        vm.stopPrank();
    }

    function testFeeWithdrawalShouldReturnTheWithdrawnFeeAmount() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);

        uint256 withdrawAmount = 10;
        token0.safeTransfer(address(carbonController), withdrawAmount);
        carbonController.testSetAccumulatedFees(token0, withdrawAmount);
        uint256 feeAmount = carbonController.withdrawFees(token0, withdrawAmount, admin);

        assertEq(withdrawAmount, feeAmount);

        vm.stopPrank();
    }

    function testFeeWithdrawalShouldCapTheFeeAmountToTheAvailableBalance() public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);

        uint256 feeAmount = 10;
        uint256 withdrawAmount = feeAmount + 1;
        token0.safeTransfer(address(carbonController), feeAmount);
        carbonController.testSetAccumulatedFees(token0, feeAmount);
        uint256 feeReturnAmount = carbonController.withdrawFees(token0, withdrawAmount, admin);

        assertEq(feeAmount, feeReturnAmount);

        vm.stopPrank();
    }

    function testFeeWithdrawalBalancesAreUpdatedCorrectly(bool t0, uint256 feeAmount, uint256 withdrawAmount) public {
        vm.startPrank(admin);
        carbonController.grantRole(carbonController.roleFeesManager(), admin);
        // use two of the below tokens for the fee withdrawal
        Token[2] memory tokens = [token0, token1];
        uint256 i = t0 ? 0 : 1;
        // bound feeAmount from 1 to 8000000
        // bound withdrawAmount from feeAmount to 8000000
        feeAmount = bound(feeAmount, 1, 8000000);
        withdrawAmount = bound(withdrawAmount, feeAmount, 8000000);

        tokens[i].safeTransfer(address(carbonController), feeAmount);

        // get balances before
        // 0 -> token admin
        // 1 -> token controller
        uint256[2] memory balancesBefore = [tokens[i].balanceOf(admin), tokens[i].balanceOf(address(carbonController))];

        carbonController.testSetAccumulatedFees(tokens[i], feeAmount);
        carbonController.withdrawFees(tokens[i], withdrawAmount, admin);

        // get balances after
        // 0 -> token admin
        // 1 -> token controller
        uint256[2] memory balancesAfter = [tokens[i].balanceOf(admin), tokens[i].balanceOf(address(carbonController))];

        // admin balance should increase by fee amount
        assertEq(balancesAfter[0], balancesBefore[0] + feeAmount);

        // controller balance should decrease by fee amount
        assertEq(balancesAfter[1], balancesBefore[1] - feeAmount);

        vm.stopPrank();
    }

    /// @dev helper function to compare strategy structs
    function compareStrategyStructs(Strategy memory strategy1, Strategy memory strategy2) private pure returns (bool) {
        if (
            strategy1.id != strategy2.id ||
            strategy1.owner != strategy2.owner ||
            strategy1.tokens[0] != (strategy2.tokens[0]) ||
            strategy1.tokens[1] != (strategy2.tokens[1]) ||
            !compareOrders(strategy1.orders[0], strategy2.orders[0]) ||
            !compareOrders(strategy1.orders[1], strategy2.orders[1])
        ) {
            return false;
        }
        return true;
    }

    /// @dev helper function to compare order structs
    function compareOrders(Order memory order1, Order memory order2) private pure returns (bool) {
        if (order1.y != order2.y || order1.z != order2.z || order1.A != order2.A || order1.B != order2.B) {
            return false;
        }
        return true;
    }

    /// @dev helper function to update an Order with a given delta
    function updateOrderDelta(Order memory initialOrder, int64 delta) private pure returns (Order memory order) {
        // delta should be less than int64
        assert(delta <= type(int64).max);
        if (delta >= 0) {
            return
                Order({
                    y: initialOrder.y + abs(delta),
                    z: initialOrder.z + abs(delta),
                    A: initialOrder.A + abs(delta),
                    B: initialOrder.B + abs(delta)
                });
        } else {
            return
                Order({
                    y: initialOrder.y - abs(delta),
                    z: initialOrder.z - abs(delta),
                    A: initialOrder.A - abs(delta),
                    B: initialOrder.B - abs(delta)
                });
        }
    }

    /// @dev helper function to generate test order with custom y amount
    function generateTestOrder(uint256 amount) private pure returns (Order memory order) {
        // amount should be less than uint128
        assert(amount <= type(uint128).max);
        return Order({ y: uint128(amount), z: 8000000, A: 736899889, B: 12148001999 });
    }

    /// @dev helper function to generate test order
    function generateTestOrder() private pure returns (Order memory order) {
        return Order({ y: 800000, z: 8000000, A: 736899889, B: 12148001999 });
    }

    /// @dev helper function to generate a disabled order (with all zeroed values)
    function generateDisabledOrder() private pure returns (Order memory order) {
        return Order({ y: 0, z: 0, A: 0, B: 0 });
    }

    function generateStrategyId(uint256 pairId, uint256 strategyIndex) private pure returns (uint256) {
        return (pairId << 128) | strategyIndex;
    }

    /// @dev get value to send with strategy update
    function getValueToSend(Token token0, Token token1, int64 delta0, int64 delta1) private pure returns (uint256 val) {
        val = token0 == NATIVE_TOKEN && delta0 >= 0 ? uint64(delta0) : 0;
        val += token1 == NATIVE_TOKEN && delta1 >= 0 ? uint64(delta1) : 0;
    }

    function abs(int64 val) private pure returns (uint64) {
        return val < 0 ? uint64(-val) : uint64(val);
    }
}
