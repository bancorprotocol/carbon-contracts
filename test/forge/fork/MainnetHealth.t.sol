// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Test, Vm } from "forge-std/Test.sol";

import { IAccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/IAccessControlEnumerableUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TestCaseParser } from "../TestCaseParser.t.sol";

import { ICarbonController } from "../../../contracts/carbon/interfaces/ICarbonController.sol";
import { ICarbonVortex } from "../../../contracts/vortex/interfaces/ICarbonVortex.sol";
import { ICarbonPOL } from "../../../contracts/pol/interfaces/ICarbonPOL.sol";
import { IVoucher } from "../../../contracts/voucher/interfaces/IVoucher.sol";
import { CarbonController } from "../../../contracts/carbon/CarbonController.sol";
import { CarbonBatcher, StrategyData } from "../../../contracts/utility/CarbonBatcher.sol";
import { Order, Strategy, TradeAction, Strategies } from "../../../contracts/carbon/Strategies.sol";
import { Upgradeable } from "../../../contracts/utility/Upgradeable.sol";
import { AccessDenied, InvalidAddress } from "../../../contracts/utility/Utils.sol";
import { MathEx } from "../../../contracts/utility/MathEx.sol";
import { Token, NATIVE_TOKEN } from "../../../contracts/token/Token.sol";
import { PPM_RESOLUTION } from "../../../contracts/utility/Constants.sol";

interface IPostUpgrade {
    function postUpgrade(bool checkVersion, bytes calldata data) external;
}

/// @dev signature used by implementations deployed before the checkVersion flag was added
interface IPostUpgradeLegacy {
    function postUpgrade(bytes calldata data) external;
}

/**
 * @dev Health check of the live mainnet deployment, run against a fork.
 *
 * Addresses come from deployments/mainnet and the RPC from utils/rpcUrls.json,
 * the suite only runs when FORK_TESTS is set.
 *
 *   FORK_TESTS=1 forge test --match-path 'test/forge/fork/*' -vv
 *
 * MAINNET_RPC_URL overrides the configured endpoint, e.g. to use an archive key in CI.
 *
 * Replaces deploy/tests/mainnet/carbon.ts in the health job, except running pending deployments
 * (`pnpm test:deploy:mainnet` still does that). Storage gaps are checked by deployments/check-storage-gaps.sh.
 */
contract MainnetHealthTest is Test {
    error TokensTradedNotEmitted();
    error StrategyCreatedNotEmitted();
    error VoucherTransferNotEmitted();
    error UnknownTokenSymbol(string symbol);

    event StrategyCreated(
        uint256 id,
        address indexed owner,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1
    );
    event StrategyUpdated(
        uint256 indexed id,
        Token indexed token0,
        Token indexed token1,
        Order order0,
        Order order1,
        uint8 reason
    );
    event TokensTraded(
        address indexed trader,
        Token indexed sourceToken,
        Token indexed targetToken,
        uint256 sourceAmount,
        uint256 targetAmount,
        uint128 tradingFeeAmount,
        bool byTargetAmount
    );

    // mainnet tokens (mirrors data/named-accounts.ts)
    Token private constant BNT = Token.wrap(0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C);
    Token private constant DAI = Token.wrap(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    Token private constant USDC = Token.wrap(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // mainnet admins
    address private constant ADMIN_OWNER = 0xe01EA58F6DA98488E4C92fD9b3E49607639C5370;
    address private constant DEPLOYER = 0x5bEBA4D3533a963Dedb270a95ae5f7752fA0Fe22;

    // EIP-1967 implementation slot
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 private constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 private constant ROLE_FEES_MANAGER = keccak256("ROLE_FEES_MANAGER");

    bytes32 private constant TOKENS_TRADED_SIG =
        keccak256("TokensTraded(address,address,address,uint256,uint256,uint128,bool)");
    bytes32 private constant STRATEGY_CREATED_SIG =
        keccak256(
            "StrategyCreated(uint256,address,address,address,(uint128,uint128,uint64,uint64),(uint128,uint128,uint64,uint64))"
        );
    bytes32 private constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");

    uint8 private constant STRATEGY_UPDATE_REASON_TRADE = 1;
    uint256 private constant EXCESS_NATIVE_VALUE = 10_000;

    ICarbonController private carbonController;
    IVoucher private voucher;
    ICarbonVortex private carbonVortex;
    ICarbonPOL private carbonPOL;
    CarbonBatcher private carbonBatcher;
    address private proxyAdmin;
    TestCaseParser private testCaseParser;

    address private marketMaker = makeAddr("marketMaker");
    address private trader = makeAddr("trader");
    address private nonAdmin = makeAddr("nonAdmin"); // must be denied on every admin-only path
    address private executor = makeAddr("executor"); // permissionless caller of vortex execute, earns the reward

    struct TradeExpectation {
        uint256 sourceAmount; // what the trader pays, fee included when trading by target
        uint256 targetAmount; // what the trader receives, fee deducted when trading by source
        uint128 fee;
    }

    struct Balances {
        uint256 sourceFees;
        uint256 targetFees;
        uint256 traderSource;
        uint256 traderTarget;
    }

    struct UpdateCase {
        Token token0;
        Token token1;
        int256 delta0;
        int256 delta1;
        bool excessNativeValue;
    }

    function setUp() public {
        if (!vm.envOr("FORK_TESTS", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(_rpcUrl("mainnet"));

        carbonController = ICarbonController(_deployment("CarbonController_Proxy"));
        voucher = IVoucher(_deployment("Voucher_Proxy"));
        carbonVortex = ICarbonVortex(_deployment("CarbonVortex_Proxy"));
        carbonPOL = ICarbonPOL(_deployment("CarbonPOL_Proxy"));
        carbonBatcher = CarbonBatcher(payable(_deployment("CarbonBatcher_Proxy")));
        proxyAdmin = _deployment("ProxyAdmin");
        testCaseParser = new TestCaseParser();
    }

    // =============================================================================================
    // deployment integrity
    // =============================================================================================

    /// @dev what is live on chain must match what the repo's deployment artifacts say
    function testImplementationsMatchDeploymentArtifacts() public view {
        _assertImplementation("CarbonController", address(carbonController));
        _assertImplementation("Voucher", address(voucher));
        _assertImplementation("CarbonVortex", address(carbonVortex));
        _assertImplementation("CarbonPOL", address(carbonPOL));
        _assertImplementation("CarbonBatcher", address(carbonBatcher));
    }

    /// @dev implementation contracts must not be initializable by anyone (Initializable._initialized != 0)
    function testImplementationsAreLocked() public view {
        _assertImplementationLocked("CarbonController");
        _assertImplementationLocked("Voucher");
        _assertImplementationLocked("CarbonVortex");
        _assertImplementationLocked("CarbonPOL");
        _assertImplementationLocked("CarbonBatcher");
    }

    /// @dev proxy admins are immutable and ProxyAdmin_Old is renounced, so this owner is the only upgrade authority
    function testUpgradeAuthority() public view {
        assertEq(Ownable(proxyAdmin).owner(), ADMIN_OWNER, "unexpected ProxyAdmin owner");
    }

    /// @dev postUpgrade must be consumable at most once more on every proxy, and locked after that
    function testPostUpgradeCannotBeReplayed() public {
        _assertPostUpgradeLocked("CarbonController", address(carbonController));
        _assertPostUpgradeLocked("Voucher", address(voucher));
        _assertPostUpgradeLocked("CarbonVortex", address(carbonVortex));
        _assertPostUpgradeLocked("CarbonPOL", address(carbonPOL));
        _assertPostUpgradeLocked("CarbonBatcher", address(carbonBatcher));
    }

    // =============================================================================================
    // roles and wiring
    // =============================================================================================

    function testRoles() public view {
        _assertSoleRoleMember("CarbonController", address(carbonController), ROLE_FEES_MANAGER, address(carbonVortex));
        assertEq(voucher.controller(), address(carbonController), "unexpected voucher controller");
    }

    function testAdminRoleHeldByExpectedAccount() public view {
        _assertSoleRoleMember("CarbonController", address(carbonController), ROLE_ADMIN, ADMIN_OWNER);
        _assertSoleRoleMember("CarbonVortex", address(carbonVortex), ROLE_ADMIN, ADMIN_OWNER);
        _assertSoleRoleMember("Voucher", address(voucher), ROLE_ADMIN, DEPLOYER);
        _assertSoleRoleMember("CarbonPOL", address(carbonPOL), ROLE_ADMIN, DEPLOYER);
        _assertSoleRoleMember("CarbonBatcher", address(carbonBatcher), ROLE_ADMIN, DEPLOYER);
    }

    function testAdminCanChangeFeesAndNonAdminCannot() public {
        address admin = IAccessControlEnumerableUpgradeable(address(carbonController)).getRoleMember(ROLE_ADMIN, 0);
        uint32 current = carbonController.tradingFeePPM();
        uint32 changed = current == 3000 ? 3001 : 3000;

        vm.prank(nonAdmin);
        vm.expectRevert(AccessDenied.selector);
        CarbonController(address(carbonController)).setTradingFeePPM(changed);

        vm.prank(admin);
        CarbonController(address(carbonController)).setTradingFeePPM(changed);
        assertEq(carbonController.tradingFeePPM(), changed);
    }

    function testVortexWiring() public view {
        address[] memory controllers = carbonVortex.controllers();
        assertEq(controllers.length, 1);
        assertEq(controllers[0], address(carbonController));
        assertEq(Token.unwrap(carbonVortex.targetToken()), Token.unwrap(NATIVE_TOKEN));
        assertEq(Token.unwrap(carbonVortex.finalTargetToken()), Token.unwrap(BNT));
        assertTrue(carbonVortex.transferAddress() != address(0));
        assertGt(carbonVortex.rewardsPPM(), 0);
        assertLt(carbonVortex.rewardsPPM(), PPM_RESOLUTION);
    }

    function testPolConfigured() public view {
        assertGt(carbonPOL.marketPriceMultiply(), 0);
        assertGt(carbonPOL.priceDecayHalfLife(), 0);
    }

    // =============================================================================================
    // strategy creation
    // =============================================================================================

    /// @dev the full strategy struct round-trips for every token ordering, native token on either side
    function testCreateStrategyStoresInformationForEachPairOrdering() public {
        Token[2][3] memory pairs = _creationPairs();
        for (uint256 p = 0; p < pairs.length; p++) {
            Order[2] memory orders = [_stdOrder(), _stdOrder()];
            orders[0].y = 100;
            orders[1].y = 100;

            uint256 id = _createStrategy(marketMaker, pairs[p][0], pairs[p][1], orders, 0, true);

            Strategy memory stored = carbonController.strategy(id);
            assertEq(stored.id, id);
            assertEq(stored.owner, marketMaker);
            assertEq(Token.unwrap(stored.tokens[0]), Token.unwrap(pairs[p][0]));
            assertEq(Token.unwrap(stored.tokens[1]), Token.unwrap(pairs[p][1]));
            _assertOrderEq(stored.orders[0], orders[0], "order0");
            _assertOrderEq(stored.orders[1], orders[1], "order1");
        }
    }

    function testCreateStrategyRevertsOnInvalidTokens() public {
        Order memory order = _testOrder();
        Order[2] memory orders = [order, order];
        Token zero = Token.wrap(address(0));

        vm.startPrank(marketMaker);
        vm.expectRevert(InvalidAddress.selector);
        carbonController.createStrategy(DAI, zero, orders);

        vm.expectRevert(InvalidAddress.selector);
        carbonController.createStrategy(zero, BNT, orders);

        vm.expectRevert(InvalidAddress.selector);
        carbonController.createStrategy(zero, zero, orders);

        vm.expectRevert(CarbonController.IdenticalAddresses.selector);
        carbonController.createStrategy(BNT, BNT, orders);
        vm.stopPrank();
    }

    function testCreateStrategyEmitsStrategyCreatedAndVoucherTransfer() public {
        Order[2] memory orders = [_stdOrder(), _stdOrder()];

        vm.recordLogs();
        uint256 id = _createStrategy(marketMaker, BNT, DAI, orders, 0, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // StrategyCreated(id, owner, token0, token1, order0, order1) with owner and tokens indexed
        bool created;
        bool minted;
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.emitter == address(carbonController) && log.topics[0] == STRATEGY_CREATED_SIG) {
                assertEq(address(uint160(uint256(log.topics[1]))), marketMaker);
                assertEq(address(uint160(uint256(log.topics[2]))), Token.unwrap(BNT));
                assertEq(address(uint160(uint256(log.topics[3]))), Token.unwrap(DAI));
                (uint256 emittedId, Order memory o0, Order memory o1) = abi.decode(log.data, (uint256, Order, Order));
                assertEq(emittedId, id);
                _assertOrderEq(o0, orders[0], "emitted order0");
                _assertOrderEq(o1, orders[1], "emitted order1");
                created = true;
            }
            // ERC721 Transfer(from, to, tokenId) has all three params indexed
            if (
                log.emitter == address(voucher) &&
                log.topics.length == 4 &&
                log.topics[0] == TRANSFER_SIG &&
                log.topics[1] == bytes32(0) &&
                address(uint160(uint256(log.topics[2]))) == marketMaker &&
                uint256(log.topics[3]) == id
            ) {
                minted = true;
            }
        }
        if (!created) revert StrategyCreatedNotEmitted();
        if (!minted) revert VoucherTransferNotEmitted();
    }

    function testCreateStrategyMintsVoucherAndPullsFunds() public {
        Order memory order = _testOrder();
        uint256 controllerBnt = _bal(BNT, address(carbonController));
        uint256 controllerDai = _bal(DAI, address(carbonController));
        uint256 vouchersBefore = voucher.balanceOf(marketMaker);

        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        Strategy memory created = carbonController.strategy(strategyId);
        assertEq(created.owner, marketMaker);
        assertEq(Token.unwrap(created.tokens[0]), Token.unwrap(BNT));
        assertEq(Token.unwrap(created.tokens[1]), Token.unwrap(DAI));
        assertEq(created.orders[0].y, order.y);
        assertEq(created.orders[1].y, order.y);

        assertEq(voucher.ownerOf(strategyId), marketMaker);
        assertEq(voucher.balanceOf(marketMaker), vouchersBefore + 1);
        assertEq(_bal(BNT, address(carbonController)) - controllerBnt, order.y);
        assertEq(_bal(DAI, address(carbonController)) - controllerDai, order.y);
    }

    function testCreateStrategyWithNativeToken() public {
        Order memory order = _testOrder();
        uint256 controllerEth = address(carbonController).balance;

        uint256 strategyId = _createNativeStrategy(marketMaker, order);

        assertEq(address(carbonController).balance - controllerEth, order.y);
        assertEq(carbonController.strategy(strategyId).owner, marketMaker);
    }

    /// @dev owner pays exactly the liquidity and the controller receives exactly that, for every token ordering
    function testCreateStrategyUpdatesBalancesForEachPairOrdering() public {
        Token[2][3] memory pairs = _creationPairs();
        for (uint256 p = 0; p < pairs.length; p++) {
            Token t0 = pairs[p][0];
            Token t1 = pairs[p][1];
            Order[2] memory orders = [_stdOrder(), _stdOrder()];
            orders[0].y = 100;
            orders[1].y = 100;

            // fund and approve up front so the create call itself moves nothing else
            _give(t0, marketMaker, 100);
            _give(t1, marketMaker, 100);
            _approve(t0, marketMaker, 100);
            _approve(t1, marketMaker, 100);

            uint256 ownerT0 = _bal(t0, marketMaker);
            uint256 ownerT1 = _bal(t1, marketMaker);
            uint256 controllerT0 = _bal(t0, address(carbonController));
            uint256 controllerT1 = _bal(t1, address(carbonController));

            _createStrategy(marketMaker, t0, t1, orders, 0, false);

            assertEq(ownerT0 - _bal(t0, marketMaker), 100, "owner token0");
            assertEq(ownerT1 - _bal(t1, marketMaker), 100, "owner token1");
            assertEq(_bal(t0, address(carbonController)) - controllerT0, 100, "controller token0");
            assertEq(_bal(t1, address(carbonController)) - controllerT1, 100, "controller token1");
        }
    }

    function testBatcherCreatesStrategiesAndForwardsVouchers() public {
        Order memory order = _testOrder();
        StrategyData[] memory strategies = new StrategyData[](2);
        strategies[0] = StrategyData({ tokens: [BNT, DAI], orders: [order, order] });
        strategies[1] = StrategyData({ tokens: [BNT, USDC], orders: [order, order] });

        deal(Token.unwrap(BNT), marketMaker, 2 * uint256(order.y));
        deal(Token.unwrap(DAI), marketMaker, order.y);
        deal(Token.unwrap(USDC), marketMaker, order.y);

        vm.startPrank(marketMaker);
        IERC20(Token.unwrap(BNT)).approve(address(carbonBatcher), 2 * uint256(order.y));
        IERC20(Token.unwrap(DAI)).approve(address(carbonBatcher), order.y);
        IERC20(Token.unwrap(USDC)).approve(address(carbonBatcher), order.y);
        uint256[] memory ids = carbonBatcher.batchCreate(strategies);
        vm.stopPrank();

        assertEq(ids.length, 2);
        for (uint256 i = 0; i < ids.length; ++i) {
            assertEq(voucher.ownerOf(ids[i]), marketMaker, "voucher not forwarded to caller");
            assertEq(carbonController.strategy(ids[i]).owner, marketMaker);
        }
        // the batcher must not retain anything
        assertEq(_bal(BNT, address(carbonBatcher)), 0);
        assertEq(_bal(DAI, address(carbonBatcher)), 0);
        assertEq(_bal(USDC, address(carbonBatcher)), 0);
    }

    // =============================================================================================
    // strategy updates
    // =============================================================================================

    /// @dev all four order fields shifted by +100 on one side and -100 on the other, for every token ordering
    function testUpdateStrategyStoresOrdersForEachPairOrdering() public {
        Token[2][3] memory pairs = _updatePairs();
        for (uint256 p = 0; p < pairs.length; p++) {
            Order[2] memory current = [_stdOrder(), _stdOrder()];
            uint256 id = _createStrategy(marketMaker, pairs[p][0], pairs[p][1], current, 0, true);

            Order[2] memory updated = [_shifted(current[0], 100), _shifted(current[1], -100)];
            _updateStrategy(marketMaker, id, current, updated, 0, true);

            Strategy memory stored = carbonController.strategy(id);
            assertEq(stored.id, id);
            assertEq(stored.owner, marketMaker);
            assertEq(Token.unwrap(stored.tokens[0]), Token.unwrap(pairs[p][0]));
            assertEq(Token.unwrap(stored.tokens[1]), Token.unwrap(pairs[p][1]));
            _assertOrderEq(stored.orders[0], updated[0], "order0");
            _assertOrderEq(stored.orders[1], updated[1], "order1");
        }
    }

    /// @dev z, A and B change while y stays the same, so no funds move
    function testUpdateStrategyStoresOrdersWithoutLiquidityChange() public {
        Token[2][3] memory pairs = _updatePairs();
        for (uint256 p = 0; p < pairs.length; p++) {
            Order[2] memory current = [_stdOrder(), _stdOrder()];
            uint256 id = _createStrategy(marketMaker, pairs[p][0], pairs[p][1], current, 0, true);

            Order[2] memory updated = [_shiftedKeepingY(current[0], 1), _shiftedKeepingY(current[1], -1)];
            uint256 ownerT0 = _bal(pairs[p][0], marketMaker);
            uint256 ownerT1 = _bal(pairs[p][1], marketMaker);

            vm.prank(marketMaker);
            carbonController.updateStrategy(id, current, updated);

            Strategy memory stored = carbonController.strategy(id);
            _assertOrderEq(stored.orders[0], updated[0], "order0");
            _assertOrderEq(stored.orders[1], updated[1], "order1");
            assertEq(_bal(pairs[p][0], marketMaker), ownerT0, "owner token0 moved");
            assertEq(_bal(pairs[p][1], marketMaker), ownerT1, "owner token1 moved");
        }
    }

    /// @dev deposits and withdrawals on update move exactly the delta, and excess native value is refunded
    function testUpdateStrategyUpdatesBalancesForEachCase() public {
        UpdateCase[5] memory cases = [
            UpdateCase(BNT, DAI, 100, -100, false),
            UpdateCase(BNT, NATIVE_TOKEN, 100, -100, false),
            UpdateCase(NATIVE_TOKEN, BNT, 100, -100, false),
            UpdateCase(BNT, NATIVE_TOKEN, 100, 100, true),
            UpdateCase(NATIVE_TOKEN, BNT, 100, 100, true)
        ];
        for (uint256 c = 0; c < cases.length; c++) {
            _runUpdateBalanceCase(cases[c]);
        }
    }

    function testUpdateStrategyMovesLiquidityBothWays() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        uint128 delta = 1000;
        Order[2] memory current = [_clone(order), _clone(order)];
        Order[2] memory updated = [_clone(order), _clone(order)];
        updated[0].y = order.y + delta; // deposit BNT
        updated[0].z = order.z + delta; // capacity must cover the new liquidity
        updated[1].y = order.y - delta; // withdraw DAI

        uint256 bntBefore = _bal(BNT, marketMaker);
        uint256 daiBefore = _bal(DAI, marketMaker);

        vm.startPrank(marketMaker);
        IERC20(Token.unwrap(BNT)).approve(address(carbonController), delta);
        carbonController.updateStrategy(strategyId, current, updated);
        vm.stopPrank();

        Strategy memory stored = carbonController.strategy(strategyId);
        assertEq(stored.orders[0].y, updated[0].y);
        assertEq(stored.orders[1].y, updated[1].y);
        assertEq(bntBefore - _bal(BNT, marketMaker), delta);
        assertEq(_bal(DAI, marketMaker) - daiBefore, delta);
    }

    function testUpdateStrategyRejectsStaleOrders() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        Order memory stale = order;
        stale.y = order.y - 1;

        vm.prank(marketMaker);
        vm.expectRevert(Strategies.OutDated.selector);
        carbonController.updateStrategy(strategyId, [stale, order], [order, order]);
    }

    function testUpdateStrategyRefundsExcessNativeToken() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createNativeStrategy(marketMaker, order);
        Strategy memory stored = carbonController.strategy(strategyId);
        uint256 ethIndex = stored.tokens[0].isNative() ? 0 : 1;

        uint128 delta = 1000;
        Order[2] memory updated = [_clone(stored.orders[0]), _clone(stored.orders[1])];
        updated[ethIndex].y += delta;
        updated[ethIndex].z += delta;

        uint256 ethBefore = marketMaker.balance;
        vm.prank(marketMaker);
        carbonController.updateStrategy{ value: delta + 1 ether }(strategyId, stored.orders, updated);

        // only the deposited delta is kept, the excess ether comes back
        assertEq(ethBefore - marketMaker.balance, delta);
        assertEq(carbonController.strategy(strategyId).orders[ethIndex].y, updated[ethIndex].y);
    }

    function testDeleteStrategyReturnsFundsAndBurnsVoucher() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        uint256 bntBefore = _bal(BNT, marketMaker);
        uint256 daiBefore = _bal(DAI, marketMaker);

        vm.prank(marketMaker);
        carbonController.deleteStrategy(strategyId);

        assertEq(_bal(BNT, marketMaker) - bntBefore, order.y);
        assertEq(_bal(DAI, marketMaker) - daiBefore, order.y);
        vm.expectRevert(bytes("ERC721: invalid token ID"));
        voucher.ownerOf(strategyId);
    }

    function testNonOwnerCannotUpdateOrDeleteStrategy() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        vm.startPrank(nonAdmin);
        vm.expectRevert(AccessDenied.selector);
        carbonController.updateStrategy(strategyId, [order, order], [order, order]);
        vm.expectRevert(AccessDenied.selector);
        carbonController.deleteStrategy(strategyId);
        vm.stopPrank();
    }

    // =============================================================================================
    // trading with the shared test cases (test/helpers/data/tradeTestDataForge.json)
    // =============================================================================================

    /// @dev nine strategies with real curves, one trade across all of them, checked against the expected
    /// orders the SDK computed; the same cases the hardhat health suite ran and the forge unit tests run
    function testTradeTestCaseBntToDaiBySource() public {
        _runTradeTestCase("BNT", "DAI", false);
    }

    function testTradeTestCaseBntToDaiByTarget() public {
        _runTradeTestCase("BNT", "DAI", true);
    }

    function testTradeTestCaseEthToUsdcBySource() public {
        _runTradeTestCase("ETH", "USDC", false);
    }

    function testTradeTestCaseEthToUsdcByTarget() public {
        _runTradeTestCase("ETH", "USDC", true);
    }

    // =============================================================================================
    // trading, single flat order
    // =============================================================================================

    function testTradeBySourceAmount() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        // trader sells DAI for BNT: consumes order 0 (BNT liquidity), fills order 1 (DAI side)
        uint128 sourceAmount = 100_000;
        TradeAction[] memory actions = _single(strategyId, sourceAmount);
        uint128 quoted = carbonController.calculateTradeTargetAmount(DAI, BNT, actions);
        assertGt(quoted, 0);

        deal(Token.unwrap(DAI), trader, sourceAmount);
        uint256 bntBefore = _bal(BNT, trader);

        vm.startPrank(trader);
        IERC20(Token.unwrap(DAI)).approve(address(carbonController), sourceAmount);
        uint128 received = carbonController.tradeBySourceAmount(DAI, BNT, actions, block.timestamp + 1, quoted);
        vm.stopPrank();

        assertEq(received, quoted);
        assertEq(_bal(BNT, trader) - bntBefore, received);
        assertEq(_bal(DAI, trader), 0);

        // liquidity moved between the two orders; the trading fee is kept by the controller on one side
        uint256 fee = (uint256(sourceAmount) * carbonController.pairTradingFeePPM(BNT, DAI)) / PPM_RESOLUTION;
        Strategy memory updated = carbonController.strategy(strategyId);
        assertLe(updated.orders[0].y, order.y - received);
        assertGe(updated.orders[0].y, order.y - received - fee - 1);
        assertGe(updated.orders[1].y, order.y + sourceAmount - fee - 1);
        assertLe(updated.orders[1].y, order.y + sourceAmount);
    }

    function testTradeByTargetAmount() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        uint128 targetAmount = 100_000;
        TradeAction[] memory actions = _single(strategyId, targetAmount);
        uint128 quotedInput = carbonController.calculateTradeSourceAmount(DAI, BNT, actions);
        assertGt(quotedInput, targetAmount, "input must cover target plus fee");

        deal(Token.unwrap(DAI), trader, quotedInput);
        uint256 bntBefore = _bal(BNT, trader);

        vm.recordLogs();
        vm.startPrank(trader);
        IERC20(Token.unwrap(DAI)).approve(address(carbonController), quotedInput);
        uint128 spent = carbonController.tradeByTargetAmount(DAI, BNT, actions, block.timestamp + 1, quotedInput);
        vm.stopPrank();

        assertEq(spent, quotedInput);
        assertEq(_bal(BNT, trader) - bntBefore, targetAmount);
        assertEq(_bal(DAI, trader), 0);

        (uint256 evSource, uint256 evTarget, , bool byTarget) = _lastTokensTraded();
        assertEq(evSource, spent);
        assertEq(evTarget, targetAmount);
        assertTrue(byTarget);
    }

    function testTradeRecordsFeeInAccumulatedFees() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        uint128 sourceAmount = 100_000;
        TradeAction[] memory actions = _single(strategyId, sourceAmount);
        deal(Token.unwrap(DAI), trader, sourceAmount);

        uint256 feesBntBefore = carbonController.accumulatedFees(BNT);
        uint256 feesDaiBefore = carbonController.accumulatedFees(DAI);

        vm.recordLogs();
        vm.startPrank(trader);
        IERC20(Token.unwrap(DAI)).approve(address(carbonController), sourceAmount);
        carbonController.tradeBySourceAmount(DAI, BNT, actions, block.timestamp + 1, 1);
        vm.stopPrank();

        (, , uint128 feeAmount, bool byTarget) = _lastTokensTraded();
        assertFalse(byTarget);
        assertGt(feeAmount, 0, "a non-zero fee is expected at the live fee rate");

        // the fee lands on exactly one side and matches the event
        uint256 bntDelta = carbonController.accumulatedFees(BNT) - feesBntBefore;
        uint256 daiDelta = carbonController.accumulatedFees(DAI) - feesDaiBefore;
        assertEq(bntDelta + daiDelta, feeAmount);
        assertTrue(bntDelta == 0 || daiDelta == 0);
    }

    function testTradeNativeSourceRefundsExcess() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createNativeStrategy(marketMaker, order);

        // trader buys USDC with ETH by target amount, sending more ether than needed
        uint128 targetAmount = 50_000;
        TradeAction[] memory actions = _single(strategyId, targetAmount);
        uint128 quotedInput = carbonController.calculateTradeSourceAmount(NATIVE_TOKEN, USDC, actions);
        assertGt(quotedInput, 0);

        deal(trader, 10 ether);
        uint256 ethBefore = trader.balance;

        vm.prank(trader);
        uint128 spent = carbonController.tradeByTargetAmount{ value: quotedInput + 1 ether }(
            NATIVE_TOKEN,
            USDC,
            actions,
            block.timestamp + 1,
            quotedInput
        );

        assertEq(spent, quotedInput);
        assertEq(ethBefore - trader.balance, quotedInput, "excess ether was not refunded");
        assertEq(_bal(USDC, trader), targetAmount);
    }

    function testTradeNativeTarget() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createNativeStrategy(marketMaker, order);

        uint128 sourceAmount = 50_000;
        TradeAction[] memory actions = _single(strategyId, sourceAmount);
        uint128 quoted = carbonController.calculateTradeTargetAmount(USDC, NATIVE_TOKEN, actions);
        assertGt(quoted, 0);

        deal(Token.unwrap(USDC), trader, sourceAmount);
        uint256 ethBefore = trader.balance;

        vm.startPrank(trader);
        IERC20(Token.unwrap(USDC)).approve(address(carbonController), sourceAmount);
        uint128 received = carbonController.tradeBySourceAmount(
            USDC,
            NATIVE_TOKEN,
            actions,
            block.timestamp + 1,
            quoted
        );
        vm.stopPrank();

        assertEq(received, quoted);
        assertEq(trader.balance - ethBefore, received);
    }

    function testTradeRevertPaths() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);
        TradeAction[] memory actions = _single(strategyId, 100_000);

        deal(Token.unwrap(DAI), trader, 100_000);
        deal(trader, 1 ether);
        vm.startPrank(trader);
        IERC20(Token.unwrap(DAI)).approve(address(carbonController), 100_000);

        vm.expectRevert(CarbonController.DeadlineExpired.selector);
        carbonController.tradeBySourceAmount(DAI, BNT, actions, block.timestamp - 1, 1);

        vm.expectRevert(CarbonController.UnnecessaryNativeTokenReceived.selector);
        carbonController.tradeBySourceAmount{ value: 1 }(DAI, BNT, actions, block.timestamp + 1, 1);

        vm.expectRevert(Strategies.LowerThanMinReturn.selector);
        carbonController.tradeBySourceAmount(DAI, BNT, actions, block.timestamp + 1, type(uint128).max);
        vm.stopPrank();
    }

    // =============================================================================================
    // vortex
    // =============================================================================================

    /// @dev the production fee path: fees accrue in the controller, execute() pulls them into the vortex
    function testVortexExecuteCollectsFeesAndRewardsExecutor() public {
        Order memory order = _testOrder();
        uint256 strategyId = _createErc20Strategy(marketMaker, order);

        // accrue fees in both directions so DAI (auctioned) and BNT (final target, forwarded) both have fees
        _accrueFees(strategyId, DAI, BNT, 100_000);
        _accrueFees(strategyId, BNT, DAI, 100_000);

        uint256 daiFees = carbonController.accumulatedFees(DAI);
        uint256 bntFees = carbonController.accumulatedFees(BNT);
        assertGt(daiFees, 0);
        assertGt(bntFees, 0);

        uint256 vortexDai = _bal(DAI, address(carbonVortex));
        uint256 executorDai = _bal(DAI, executor);
        uint256 executorBnt = _bal(BNT, executor);
        uint256 bntSupply = IERC20(Token.unwrap(BNT)).totalSupply();

        Token[] memory tokens = new Token[](2);
        tokens[0] = DAI;
        tokens[1] = BNT;
        vm.prank(executor);
        carbonVortex.execute(tokens);

        // the controller has been drained of both
        assertEq(carbonController.accumulatedFees(DAI), 0);
        assertEq(carbonController.accumulatedFees(BNT), 0);

        // the executor was paid a reward in each token
        uint256 daiReward = _bal(DAI, executor) - executorDai;
        uint256 bntReward = _bal(BNT, executor) - executorBnt;
        assertGt(daiReward, 0);
        assertGt(bntReward, 0);

        // DAI is auctioned: it stays in the vortex and trading is live
        assertGe(_bal(DAI, address(carbonVortex)) - vortexDai + daiReward, daiFees);
        assertTrue(carbonVortex.tradingEnabled(DAI));
        assertGt(carbonVortex.amountAvailableForTrading(DAI), 0);

        // BNT is the final target: proceeds go to the transfer address, which on mainnet is the BNT
        // token itself, and BNT burns anything sent to its own address
        assertEq(carbonVortex.transferAddress(), Token.unwrap(BNT));
        uint256 burned = bntSupply - IERC20(Token.unwrap(BNT)).totalSupply();
        assertGe(burned + bntReward, bntFees);
    }

    function testVortexRejectsDuplicateTokens() public {
        Token[] memory tokens = new Token[](2);
        tokens[0] = DAI;
        tokens[1] = DAI;
        vm.expectRevert(ICarbonVortex.DuplicateToken.selector);
        carbonVortex.execute(tokens);
    }

    // =============================================================================================
    // test-case trade machinery
    // =============================================================================================

    function _runTradeTestCase(string memory sourceSymbol, string memory targetSymbol, bool byTarget) private {
        TestCaseParser.TestCase memory testCase = testCaseParser.getTestCase(sourceSymbol, targetSymbol, byTarget);
        Token source = _tokenBySymbol(sourceSymbol);
        Token target = _tokenBySymbol(targetSymbol);

        _createTestCaseStrategies(testCase, source, target);

        TradeExpectation memory expected = _expectation(testCase, source, target);
        _give(source, trader, expected.sourceAmount);
        _approve(source, trader, expected.sourceAmount);

        Balances memory before = Balances({
            sourceFees: carbonController.accumulatedFees(source),
            targetFees: carbonController.accumulatedFees(target),
            traderSource: _bal(source, trader),
            traderTarget: _bal(target, trader)
        });

        // one StrategyUpdated per trade action, in order, then the TokensTraded summary
        for (uint256 i = 0; i < testCase.strategies.length; ++i) {
            vm.expectEmit();
            emit StrategyUpdated(
                testCase.tradeActions[i].strategyId,
                source,
                target,
                testCase.strategies[i].expectedOrders[0],
                testCase.strategies[i].expectedOrders[1],
                STRATEGY_UPDATE_REASON_TRADE
            );
        }
        vm.expectEmit();
        emit TokensTraded(trader, source, target, expected.sourceAmount, expected.targetAmount, expected.fee, byTarget);

        _executeTestCaseTrade(testCase, source, target, expected);

        _assertTradeOutcome(testCase, source, target, expected, before);
    }

    function _createTestCaseStrategies(TestCaseParser.TestCase memory testCase, Token source, Token target) private {
        uint256 sourceLiquidity;
        uint256 targetLiquidity;
        for (uint256 i = 0; i < testCase.strategies.length; ++i) {
            sourceLiquidity += testCase.strategies[i].orders[0].y;
            targetLiquidity += testCase.strategies[i].orders[1].y;
        }
        _give(source, marketMaker, sourceLiquidity);
        _give(target, marketMaker, targetLiquidity);
        _approve(source, marketMaker, sourceLiquidity);
        _approve(target, marketMaker, targetLiquidity);

        for (uint256 i = 0; i < testCase.strategies.length; ++i) {
            Order[2] memory orders = testCase.strategies[i].orders;
            uint256 value = (source.isNative() ? orders[0].y : 0) + (target.isNative() ? orders[1].y : 0);
            vm.prank(marketMaker);
            uint256 id = carbonController.createStrategy{ value: value }(source, target, orders);
            // ids depend on live state, so the trade actions must point at what was just created
            testCase.tradeActions[i].strategyId = id;
        }
    }

    function _expectation(
        TestCaseParser.TestCase memory testCase,
        Token source,
        Token target
    ) private view returns (TradeExpectation memory expected) {
        uint32 feePPM = carbonController.pairTradingFeePPM(source, target);
        if (testCase.byTargetAmount) {
            uint256 withFee = MathEx.mulDivC(testCase.sourceAmount, PPM_RESOLUTION, PPM_RESOLUTION - feePPM);
            expected.fee = uint128(withFee - testCase.sourceAmount);
            expected.sourceAmount = withFee;
            expected.targetAmount = testCase.targetAmount;
        } else {
            uint256 afterFee = MathEx.mulDivF(testCase.targetAmount, PPM_RESOLUTION - feePPM, PPM_RESOLUTION);
            expected.fee = uint128(testCase.targetAmount - afterFee);
            expected.sourceAmount = testCase.sourceAmount;
            expected.targetAmount = afterFee;
        }
    }

    function _executeTestCaseTrade(
        TestCaseParser.TestCase memory testCase,
        Token source,
        Token target,
        TradeExpectation memory expected
    ) private {
        uint256 deadline = block.timestamp + 1000;
        uint256 value = source.isNative() ? expected.sourceAmount : 0;
        vm.prank(trader);
        if (testCase.byTargetAmount) {
            carbonController.tradeByTargetAmount{ value: value }(
                source,
                target,
                testCase.tradeActions,
                deadline,
                uint128(expected.sourceAmount)
            );
        } else {
            carbonController.tradeBySourceAmount{ value: value }(source, target, testCase.tradeActions, deadline, 1);
        }
    }

    function _assertTradeOutcome(
        TestCaseParser.TestCase memory testCase,
        Token source,
        Token target,
        TradeExpectation memory expected,
        Balances memory before
    ) private view {
        // the fee is booked on the source side when trading by target, on the target side otherwise
        if (testCase.byTargetAmount) {
            assertEq(carbonController.accumulatedFees(source) - before.sourceFees, expected.fee, "source fees");
            assertEq(carbonController.accumulatedFees(target), before.targetFees, "target fees");
        } else {
            assertEq(carbonController.accumulatedFees(target) - before.targetFees, expected.fee, "target fees");
            assertEq(carbonController.accumulatedFees(source), before.sourceFees, "source fees");
        }

        // the trader paid and received exactly the expected amounts
        assertEq(before.traderSource - _bal(source, trader), expected.sourceAmount, "trader source");
        assertEq(_bal(target, trader) - before.traderTarget, expected.targetAmount, "trader target");

        // every strategy now holds exactly the orders the SDK predicted
        for (uint256 i = 0; i < testCase.strategies.length; ++i) {
            Strategy memory stored = carbonController.strategy(testCase.tradeActions[i].strategyId);
            _assertOrderEq(stored.orders[0], testCase.strategies[i].expectedOrders[0], "stored order0");
            _assertOrderEq(stored.orders[1], testCase.strategies[i].expectedOrders[1], "stored order1");
        }
    }

    // =============================================================================================
    // update balance cases
    // =============================================================================================

    function _runUpdateBalanceCase(UpdateCase memory c) private {
        Order[2] memory current = [_stdOrder(), _stdOrder()];
        uint256 id = _createStrategy(marketMaker, c.token0, c.token1, current, 0, true);
        Order[2] memory updated = [_shifted(current[0], c.delta0), _shifted(current[1], c.delta1)];

        // fund and approve deposits up front so the update call itself moves nothing else; the excess
        // native value is sent along and must come back, so it is funded but not expected to move
        _fundDelta(c.token0, c.delta0);
        _fundDelta(c.token1, c.delta1);
        if (c.excessNativeValue) {
            _give(NATIVE_TOKEN, marketMaker, EXCESS_NATIVE_VALUE);
        }

        uint256 ownerT0 = _bal(c.token0, marketMaker);
        uint256 ownerT1 = _bal(c.token1, marketMaker);
        uint256 controllerT0 = _bal(c.token0, address(carbonController));
        uint256 controllerT1 = _bal(c.token1, address(carbonController));

        _updateStrategy(marketMaker, id, current, updated, c.excessNativeValue ? EXCESS_NATIVE_VALUE : 0, false);

        _assertMoved(c.token0, marketMaker, ownerT0, -c.delta0, "owner token0");
        _assertMoved(c.token1, marketMaker, ownerT1, -c.delta1, "owner token1");
        _assertMoved(c.token0, address(carbonController), controllerT0, c.delta0, "controller token0");
        _assertMoved(c.token1, address(carbonController), controllerT1, c.delta1, "controller token1");
    }

    function _fundDelta(Token token, int256 delta) private {
        if (delta > 0) {
            _give(token, marketMaker, uint256(delta));
            _approve(token, marketMaker, uint256(delta));
        }
    }

    function _assertMoved(
        Token token,
        address account,
        uint256 before,
        int256 delta,
        string memory label
    ) private view {
        int256 actual = int256(_bal(token, account)) - int256(before);
        assertEq(actual, delta, label);
    }

    // =============================================================================================
    // strategy helpers
    // =============================================================================================

    /// @dev creates a strategy as `owner`; funds and approves the liquidity first when `fund` is set
    function _createStrategy(
        address owner,
        Token token0,
        Token token1,
        Order[2] memory orders,
        uint256 extraValue,
        bool fund
    ) private returns (uint256) {
        if (fund) {
            _give(token0, owner, orders[0].y);
            _give(token1, owner, orders[1].y);
            _approve(token0, owner, orders[0].y);
            _approve(token1, owner, orders[1].y);
        }
        uint256 value = (token0.isNative() ? orders[0].y : 0) + (token1.isNative() ? orders[1].y : 0) + extraValue;
        vm.prank(owner);
        return carbonController.createStrategy{ value: value }(token0, token1, orders);
    }

    /// @dev updates a strategy as `owner`; funds and approves any deposits first when `fund` is set
    function _updateStrategy(
        address owner,
        uint256 id,
        Order[2] memory current,
        Order[2] memory updated,
        uint256 extraValue,
        bool fund
    ) private {
        Token[2] memory tokens = carbonController.strategy(id).tokens;
        uint256 value = extraValue;
        for (uint256 i = 0; i < 2; ++i) {
            if (updated[i].y > current[i].y) {
                uint256 deposit = updated[i].y - current[i].y;
                if (fund) {
                    _give(tokens[i], owner, deposit);
                    _approve(tokens[i], owner, deposit);
                }
                if (tokens[i].isNative()) {
                    value += deposit;
                }
            }
        }
        vm.prank(owner);
        carbonController.updateStrategy{ value: value }(id, current, updated);
    }

    function _createErc20Strategy(address owner, Order memory order) private returns (uint256) {
        deal(Token.unwrap(BNT), owner, 1_000_000 ether);
        deal(Token.unwrap(DAI), owner, 1_000_000 ether);

        vm.startPrank(owner);
        IERC20(Token.unwrap(BNT)).approve(address(carbonController), order.y);
        IERC20(Token.unwrap(DAI)).approve(address(carbonController), order.y);
        uint256 strategyId = carbonController.createStrategy(BNT, DAI, [order, order]);
        vm.stopPrank();
        return strategyId;
    }

    function _createNativeStrategy(address owner, Order memory order) private returns (uint256) {
        deal(owner, 10 ether);
        deal(Token.unwrap(USDC), owner, 1_000_000e6);

        vm.startPrank(owner);
        IERC20(Token.unwrap(USDC)).approve(address(carbonController), order.y);
        uint256 strategyId = carbonController.createStrategy{ value: order.y }(NATIVE_TOKEN, USDC, [order, order]);
        vm.stopPrank();
        return strategyId;
    }

    function _accrueFees(uint256 strategyId, Token source, Token target, uint128 amount) private {
        TradeAction[] memory actions = _single(strategyId, amount);
        deal(Token.unwrap(source), trader, amount);
        vm.startPrank(trader);
        IERC20(Token.unwrap(source)).approve(address(carbonController), amount);
        carbonController.tradeBySourceAmount(source, target, actions, block.timestamp + 1, 1);
        vm.stopPrank();
    }

    function _single(uint256 strategyId, uint128 amount) private pure returns (TradeAction[] memory actions) {
        actions = new TradeAction[](1);
        actions[0] = TradeAction({ strategyId: strategyId, amount: amount });
    }

    // =============================================================================================
    // token helpers
    // =============================================================================================

    /// @dev adds `amount` to `who`'s balance of `token` directly on the fork, no whales needed
    function _give(Token token, address who, uint256 amount) private {
        if (token.isNative()) {
            vm.deal(who, who.balance + amount);
        } else {
            deal(Token.unwrap(token), who, IERC20(Token.unwrap(token)).balanceOf(who) + amount);
        }
    }

    function _approve(Token token, address who, uint256 amount) private {
        if (token.isNative()) {
            return;
        }
        vm.prank(who);
        IERC20(Token.unwrap(token)).approve(address(carbonController), amount);
    }

    function _bal(Token token, address account) private view returns (uint256) {
        return token.isNative() ? account.balance : IERC20(Token.unwrap(token)).balanceOf(account);
    }

    function _tokenBySymbol(string memory symbol) private pure returns (Token) {
        bytes32 h = keccak256(bytes(symbol));
        if (h == keccak256("BNT")) return BNT;
        if (h == keccak256("DAI")) return DAI;
        if (h == keccak256("USDC")) return USDC;
        if (h == keccak256("ETH")) return NATIVE_TOKEN;
        revert UnknownTokenSymbol(symbol);
    }

    /// @dev the token orderings the hardhat suite covered for creation: native on either side, and none
    function _creationPairs() private pure returns (Token[2][3] memory pairs) {
        pairs[0] = [NATIVE_TOKEN, BNT];
        pairs[1] = [BNT, NATIVE_TOKEN];
        pairs[2] = [BNT, DAI];
    }

    function _updatePairs() private pure returns (Token[2][3] memory pairs) {
        pairs[0] = [BNT, DAI];
        pairs[1] = [BNT, NATIVE_TOKEN];
        pairs[2] = [NATIVE_TOKEN, BNT];
    }

    // =============================================================================================
    // order helpers
    // =============================================================================================

    /// @dev the standard order the hardhat helpers use (generateTestOrder)
    function _stdOrder() private pure returns (Order memory) {
        return Order({ y: 800000, z: 8000000, A: 736899889, B: 12148001999 });
    }

    /// @dev a flat order quoting 1:1
    function _testOrder() private pure returns (Order memory) {
        return Order({ y: 800_000, z: 800_000, A: 0, B: uint64((48 << 48) | 1) });
    }

    function _clone(Order memory order) private pure returns (Order memory) {
        return Order({ y: order.y, z: order.z, A: order.A, B: order.B });
    }

    /// @dev every field shifted by `delta`, the way the hardhat update tests mutate orders
    function _shifted(Order memory o, int256 delta) private pure returns (Order memory) {
        return
            Order({
                y: uint128(uint256(int256(uint256(o.y)) + delta)),
                z: uint128(uint256(int256(uint256(o.z)) + delta)),
                A: uint64(uint256(int256(uint256(o.A)) + delta)),
                B: uint64(uint256(int256(uint256(o.B)) + delta))
            });
    }

    function _shiftedKeepingY(Order memory o, int256 delta) private pure returns (Order memory) {
        Order memory shifted = _shifted(o, delta);
        shifted.y = o.y;
        return shifted;
    }

    function _assertOrderEq(Order memory actual, Order memory expected, string memory label) private pure {
        assertEq(actual.y, expected.y, string.concat(label, " y"));
        assertEq(actual.z, expected.z, string.concat(label, " z"));
        assertEq(actual.A, expected.A, string.concat(label, " A"));
        assertEq(actual.B, expected.B, string.concat(label, " B"));
    }

    // =============================================================================================
    // deployment helpers
    // =============================================================================================

    /// @dev the endpoint hardhat uses for the network, unless MAINNET_RPC_URL overrides it
    function _rpcUrl(string memory network) private view returns (string memory) {
        string memory override_ = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(override_).length != 0) {
            return override_;
        }
        string memory json = vm.readFile("utils/rpcUrls.json");
        return vm.parseJsonString(json, string.concat(".", network));
    }

    function _deployment(string memory name) private view returns (address) {
        string memory json = vm.readFile(string.concat("deployments/mainnet/", name, ".json"));
        return vm.parseJsonAddress(json, ".address");
    }

    function _assertImplementation(string memory name, address proxy) private view {
        address live = address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
        address expected = _deployment(string.concat(name, "_Implementation"));
        assertEq(live, expected, string.concat(name, " implementation drifted from deployments/mainnet"));
    }

    /// @dev OZ 4.9 Initializable keeps `uint8 _initialized` in slot 0; non-zero means initialized or disabled
    function _assertImplementationLocked(string memory name) private view {
        address impl = _deployment(string.concat(name, "_Implementation"));
        uint8 initialized = uint8(uint256(vm.load(impl, bytes32(0))));
        assertTrue(initialized != 0, string.concat(name, " implementation is not initialized"));
    }

    /// @dev postUpgrade must be consumable at most once more, and locked after that.
    function _assertPostUpgradeLocked(string memory name, address proxy) private {
        bytes memory expected = abi.encodeWithSelector(Upgradeable.AlreadyInitialized.selector);

        bytes memory callData = abi.encodeCall(IPostUpgrade.postUpgrade, (true, ""));
        // solhint-disable avoid-low-level-calls
        (bool ok, bytes memory data) = proxy.call(callData);
        if (!ok && data.length == 0) {
            callData = abi.encodeCall(IPostUpgradeLegacy.postUpgrade, (""));
            (ok, data) = proxy.call(callData);
        }
        if (ok) {
            // one pending step was consumed on the fork; it must now be locked
            (ok, data) = proxy.call(callData);
        }
        // solhint-enable avoid-low-level-calls
        assertFalse(ok, string.concat(name, ": postUpgrade can be called more than once"));
        assertEq(data, expected, string.concat(name, ": postUpgrade reverted for an unexpected reason"));
    }

    function _assertSoleRoleMember(string memory name, address target, bytes32 role, address member) private view {
        IAccessControlEnumerableUpgradeable ac = IAccessControlEnumerableUpgradeable(target);
        assertEq(ac.getRoleMemberCount(role), 1, string.concat(name, ": unexpected number of role members"));
        assertEq(ac.getRoleMember(role, 0), member, string.concat(name, ": unexpected role member"));
    }

    function _lastTokensTraded()
        private
        returns (uint256 sourceAmount, uint256 targetAmount, uint128 feeAmount, bool byTargetAmount)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory log = logs[i - 1];
            if (log.emitter == address(carbonController) && log.topics[0] == TOKENS_TRADED_SIG) {
                return abi.decode(log.data, (uint256, uint256, uint128, bool));
            }
        }
        revert TokensTradedNotEmitted();
    }
}
