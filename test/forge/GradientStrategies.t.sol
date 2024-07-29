// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import { TestFixture } from "./TestFixture.t.sol";

import { InvalidAddress } from "../../contracts/utility/Utils.sol";

import { GradientController } from "../../contracts/carbon/GradientController.sol";
import { GradientOrder, GradientStrategy, GradientStrategies, Price, GradientCurve, GradientCurveTypes } from "../../contracts/carbon/GradientStrategies.sol";
import { TestERC20FeeOnTransfer } from "../../contracts/helpers/TestERC20FeeOnTransfer.sol";

import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract GradientStrategiesTest is TestFixture {
    using Address for address payable;
    using SafeCastUpgradeable for uint256;

    uint256 private constant MSB_MASK = uint256(1) << 255;

    // strategy update reasons
    uint8 private constant STRATEGY_UPDATE_REASON_EDIT = 0;
    uint8 private constant STRATEGY_UPDATE_REASON_TRADE = 1;

    uint32 private constant DEFAULT_TRADING_FEE_PPM = 4000;
    uint32 private constant NEW_TRADING_FEE_PPM = 300_000;

    uint256 private constant FETCH_AMOUNT = 5;

    /**
     * @dev triggered when the network fee is updated
     */
    event TradingFeePPMUpdated(uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev triggered when the custom trading fee for a given pair is updated
     */
    event PairTradingFeePPMUpdated(Token indexed token0, Token indexed token1, uint32 prevFeePPM, uint32 newFeePPM);

    /**
     * @dev triggered when a gradient strategy is created
     */
    event StrategyCreated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        GradientOrder order
    );

    /**
     * @dev triggered when a gradient strategy is deleted
     */
    event StrategyDeleted(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        GradientOrder order
    );

    /**
     * @dev triggered when a gradient strategy is updated
     */
    event StrategyUpdated(
        uint256 indexed id,
        Token indexed token0,
        Token indexed token1,
        GradientOrder order,
        uint8 reason
    );

    /**
     * @dev triggered when tokens are traded
     */
    event GradientStrategyTokensTraded(
        address indexed trader,
        Token indexed sourceToken,
        Token indexed targetToken,
        uint256 sourceAmount,
        uint256 targetAmount,
        uint128 tradingFeeAmount,
        bool byTargetAmount
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
        setupGradientController();
        // Approve tokens to carbon controller
        vm.startPrank(admin);
        uint256 approveAmount = MAX_SOURCE_AMOUNT;
        token0.safeApprove(address(gradientController), approveAmount);
        token1.safeApprove(address(gradientController), approveAmount);
        token2.safeApprove(address(gradientController), approveAmount);
        vm.stopPrank();
        // Approve tokens to carbon controller
        vm.startPrank(user1);
        token0.safeApprove(address(gradientController), approveAmount);
        token1.safeApprove(address(gradientController), approveAmount);
        token2.safeApprove(address(gradientController), approveAmount);
        vm.stopPrank();
    }

    /**
     * @dev strategy creation tests
     */

    /// @dev test that the strategy creation reverts for identical token addresses
    function testStrategyCreationShouldRevertWhenTokenAddressesAreIdentical() public {
        GradientOrder memory order = generateTestOrder();
        vm.expectRevert(GradientController.IdenticalAddresses.selector);
        gradientController.createStrategy(token0, token0, order);
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

        GradientOrder memory order = generateTestOrder(amount);

        vm.expectRevert(InvalidAddress.selector);
        gradientController.createStrategy(tokens[i0], tokens[i1], order);
        vm.stopPrank();
    }

    /// @dev test that strategy creation mints a voucher token to the caller
    function testStrategyCreationMintsVoucherTokenToTheCaller() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        GradientOrder memory order = generateTestOrder(amount);
        uint256 strategyId = gradientController.createStrategy(token0, token1, order);

        uint256 balance = gradientVoucher.balanceOf(admin);
        address owner = gradientVoucher.ownerOf(strategyId);

        assertEq(balance, 1);
        assertEq(owner, admin);

        vm.stopPrank();
    }

    /// @dev test that the strategy creation emits the Voucher transfer event
    function testStrategyCreationEmitsTheVoucherTransferEvent() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        GradientOrder memory order = generateTestOrder(amount);

        uint256 strategyId = generateStrategyId(1, 1);

        vm.expectEmit();
        emit Transfer(address(0), admin, strategyId);
        gradientController.createStrategy(token0, token1, order);
        vm.stopPrank();
    }

    /// @dev test that strategy creation increases strategy id
    function testStrategyCreationIncreasesStrategyId() public {
        vm.startPrank(admin);

        uint256 amount = 1000;
        GradientOrder memory order = generateTestOrder(amount);

        uint256 firstStrategyId = gradientController.createStrategy(token0, token1, order);
        uint256 secondStrategyId = gradientController.createStrategy(token0, token1, order);
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
        // bound amounts from 1 to 10e18
        t0Amount = bound(t0Amount, 1, 10e18);
        t1Amount = bound(t1Amount, 1, 10e18);

        GradientOrder memory order = generateTestOrder(t0Amount, t1Amount);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(gradientController)),
            tokens[i1].balanceOf(address(gradientController))
        ];

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN ? t0Amount : 0;
        val = tokens[i1] == NATIVE_TOKEN ? t1Amount : val;
        gradientController.createStrategy{ value: val }(tokens[i0], tokens[i1], order);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(gradientController)),
            tokens[i1].balanceOf(address(gradientController))
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
        // bound amounts from 1 to 10e18
        t0Amount = bound(t0Amount, 1, 10e18);
        t1Amount = bound(t1Amount, 1, 10e18);

        GradientOrder memory order = generateTestOrder(t0Amount, t1Amount);

        // get balances before
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesBefore = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(gradientController)),
            tokens[i1].balanceOf(address(gradientController))
        ];

        // create strategy
        uint256 val = tokens[i0] == NATIVE_TOKEN ? t0Amount : 0;
        val = tokens[i1] == NATIVE_TOKEN ? t1Amount : val;
        // send 1 eth extra
        val += 1 ether;
        gradientController.createStrategy{ value: val }(tokens[i0], tokens[i1], order);

        // get balances after
        // 0 -> t0 user1
        // 1 -> t1 user1
        // 2 -> t0 controller
        // 3 -> t1 controller
        uint256[4] memory balancesAfter = [
            tokens[i0].balanceOf(user1),
            tokens[i1].balanceOf(user1),
            tokens[i0].balanceOf(address(gradientController)),
            tokens[i1].balanceOf(address(gradientController))
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
        GradientOrder memory order = generateTestOrder();
        vm.expectRevert(GradientController.UnnecessaryNativeTokenReceived.selector);
        gradientController.createStrategy{ value: 1000 }(token0, token1, order);
    }

    function testStrategyCreationRevertsForFeeOnTransferTokens() public {
        vm.startPrank(user1);
        uint256 amount = 1000;
        GradientOrder memory order = generateTestOrder(amount, amount);

        feeOnTransferToken.safeApprove(address(gradientController), order.targetAmount * 2);

        // test revert with negative transfer fee
        vm.expectRevert(GradientStrategies.BalanceMismatch.selector);
        gradientController.createStrategy(feeOnTransferToken, token1, order);
        vm.expectRevert(GradientStrategies.BalanceMismatch.selector);
        gradientController.createStrategy(token0, feeOnTransferToken, order);

        // change fee side
        TestERC20FeeOnTransfer(Token.unwrap(feeOnTransferToken)).setFeeSide(false);

        // test revert with positive transfer fee
        vm.expectRevert(GradientStrategies.BalanceMismatch.selector);
        gradientController.createStrategy(feeOnTransferToken, token1, order);
        vm.expectRevert(GradientStrategies.BalanceMismatch.selector);
        gradientController.createStrategy(token0, feeOnTransferToken, order);

        vm.stopPrank();
    }

    /**
     * @dev generate a test order
     */
    function generateTestOrder() private pure returns (GradientOrder memory) {
        // initialize gradient order
        Price memory initialPrice = Price({ sourceAmount: 4000e6, targetAmount: 1e18 });
        Price memory endPrice = Price({ sourceAmount: 2000e6, targetAmount: 1e18 });
        GradientCurve memory curve = GradientCurve({
            curveType: GradientCurveTypes.EXPONENTIAL,
            increaseAmount: 0,
            increaseInterval: 0,
            halflife: 1 days,
            isDutchAuction: true
        });
        GradientOrder memory order = GradientOrder({
            initialPrice: initialPrice,
            endPrice: endPrice,
            sourceAmount: 0,
            targetAmount: 1e18,
            tradingStartTime: 0,
            expiry: 0,
            tokensInverted: false,
            curve: curve
        });
        return order;
    }

    /**
     * @dev generate a test order
     */
    function generateTestOrder(uint256 targetAmount) private pure returns (GradientOrder memory) {
        // initialize gradient order
        Price memory initialPrice = Price({ sourceAmount: 4000e6, targetAmount: 1e18 });
        Price memory endPrice = Price({ sourceAmount: 2000e6, targetAmount: 1e18 });
        GradientCurve memory curve = GradientCurve({
            curveType: GradientCurveTypes.EXPONENTIAL,
            increaseAmount: 0,
            increaseInterval: 0,
            halflife: 1 days,
            isDutchAuction: true
        });
        GradientOrder memory order = GradientOrder({
            initialPrice: initialPrice,
            endPrice: endPrice,
            sourceAmount: 0,
            targetAmount: targetAmount.toUint128(),
            tradingStartTime: 0,
            expiry: 0,
            tokensInverted: false,
            curve: curve
        });
        return order;
    }

    /**
     * @dev generate a test order with two token amounts
     */
    function generateTestOrder(uint256 sourceAmount, uint256 targetAmount) private pure returns (GradientOrder memory) {
        // initialize gradient order
        Price memory initialPrice = Price({ sourceAmount: 4000e6, targetAmount: 1e18 });
        Price memory endPrice = Price({ sourceAmount: 2000e6, targetAmount: 1e18 });
        GradientCurve memory curve = GradientCurve({
            curveType: GradientCurveTypes.EXPONENTIAL,
            increaseAmount: 0,
            increaseInterval: 0,
            halflife: 1 days,
            isDutchAuction: true
        });
        GradientOrder memory order = GradientOrder({
            initialPrice: initialPrice,
            endPrice: endPrice,
            sourceAmount: sourceAmount.toUint128(),
            targetAmount: targetAmount.toUint128(),
            tradingStartTime: 0,
            expiry: 0,
            tokensInverted: false,
            curve: curve
        });
        return order;
    }

    /// @dev helper function to compare strategy structs
    function compareStrategyStructs(
        GradientStrategy memory strategy1,
        GradientStrategy memory strategy2
    ) private pure returns (bool) {
        if (
            strategy1.id != strategy2.id ||
            strategy1.owner != strategy2.owner ||
            strategy1.tokens[0] != (strategy2.tokens[0]) ||
            strategy1.tokens[1] != (strategy2.tokens[1]) ||
            !compareOrders(strategy1.order, strategy2.order)
        ) {
            return false;
        }
        return true;
    }

    /// @dev helper function to compare order structs
    function compareOrders(GradientOrder memory order1, GradientOrder memory order2) private pure returns (bool) {
        if (
            order1.initialPrice.sourceAmount != order2.initialPrice.sourceAmount ||
            order1.initialPrice.targetAmount != order2.initialPrice.targetAmount ||
            order1.endPrice.sourceAmount != order2.endPrice.sourceAmount ||
            order1.endPrice.targetAmount != order2.endPrice.targetAmount ||
            order1.sourceAmount != order2.sourceAmount ||
            order1.targetAmount != order2.targetAmount ||
            order1.tradingStartTime != order2.tradingStartTime ||
            order1.expiry != order2.expiry ||
            order1.tokensInverted != order2.tokensInverted ||
            !compareCurves(order1.curve, order2.curve)
        ) {
            return false;
        }
        return true;
    }

    function compareCurves(GradientCurve memory curve1, GradientCurve memory curve2) private pure returns (bool) {
        if (
            curve1.curveType != curve2.curveType ||
            curve1.increaseAmount != curve2.increaseAmount ||
            curve1.increaseInterval != curve2.increaseInterval ||
            curve1.halflife != curve2.halflife ||
            curve1.isDutchAuction != curve2.isDutchAuction
        ) {
            return false;
        }
        return true;
    }

    /**
     * returns the strategyId for a given pairId and a given strategyIndex
     * MSB is set to 1 to indicate gradient strategies
     */
    function generateStrategyId(uint128 pairId, uint128 strategyIndex) private pure returns (uint256) {
        return (uint256(pairId) << 128) | strategyIndex | MSB_MASK;
    }

    function sortTokens(Token token0, Token token1) private pure returns (Token[2] memory) {
        return Token.unwrap(token0) < Token.unwrap(token1) ? [token0, token1] : [token1, token0];
    }
}
