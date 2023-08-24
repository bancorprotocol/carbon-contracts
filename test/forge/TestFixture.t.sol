// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OptimizedTransparentUpgradeableProxy } from "hardhat-deploy/solc_0.8/proxy/OptimizedTransparentUpgradeableProxy.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { IStaticOracle } from "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";

import { Utilities } from "./Utilities.t.sol";

import { TestBNT } from "../../contracts/helpers/TestBNT.sol";
import { TestWETH } from "../../contracts/helpers/TestWETH.sol";
import { TestERC20Burnable } from "../../contracts/helpers/TestERC20Burnable.sol";
import { TestERC20FeeOnTransfer } from "../../contracts/helpers/TestERC20FeeOnTransfer.sol";
import { MockBancorNetworkV3 } from "../../contracts/helpers/MockBancorNetworkV3.sol";

import { MockUniswapV3Router } from "../../contracts/helpers/MockUniswapV3Router.sol";
import { MockUniswapV3Factory } from "../../contracts/helpers/MockUniswapV3Factory.sol";
import { MockUniswapV3Oracle } from "../../contracts/helpers/MockUniswapV3Oracle.sol";

import { TestVoucher } from "../../contracts/helpers/TestVoucher.sol";
import { CarbonVortex } from "../../contracts/vortex/CarbonVortex.sol";
import { TestCarbonController } from "../../contracts/helpers/TestCarbonController.sol";
import { IWETH, CarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

import { IVoucher } from "../../contracts/voucher/interfaces/IVoucher.sol";
import { ICarbonController } from "../../contracts/carbon/interfaces/ICarbonController.sol";
import { IBancorNetwork } from "../../contracts/vortex/CarbonVortex.sol";

import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

// solhint-disable max-states-count
/**
 * @dev Deploys tokens and system contracts
 */
contract TestFixture is Test {
    Utilities private utils;
    Token internal bnt;
    Token internal weth;
    Token internal token0;
    Token internal token1;
    Token internal token2;
    Token internal nonTradeableToken;
    Token internal feeOnTransferToken;

    TestVoucher internal voucher;
    CarbonVortex internal carbonVortex;
    TestCarbonController internal carbonController;
    CarbonPOL internal carbonPOL;

    ProxyAdmin internal proxyAdmin;

    address payable internal admin;
    address payable internal user1;
    address payable internal user2;
    address payable internal emergencyStopper;

    address internal constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant MAX_SOURCE_AMOUNT = 100_000_000 ether;

    function systemFixture() internal {
        utils = new Utilities();
        // create 4 users
        address payable[] memory users = utils.createUsers(4);
        admin = users[0];
        user1 = users[1];
        user2 = users[2];
        emergencyStopper = users[3];

        // deploy contracts from admin
        vm.startPrank(admin);

        // deploy proxy admin
        proxyAdmin = new ProxyAdmin();

        // deploy BNT
        bnt = Token.wrap(address(new TestBNT("Bancor Network Token", "BNT", 1_000_000_000 ether)));
        // deploy WETH
        weth = Token.wrap(address(new TestWETH()));
        // deploy test tokens
        token0 = Token.wrap(address(new TestERC20Burnable("TKN", "TKN", 1_000_000_000 ether)));
        token1 = Token.wrap(address(new TestERC20Burnable("TKN1", "TKN1", 1_000_000_000 ether)));
        token2 = Token.wrap(address(new TestERC20Burnable("TKN2", "TKN2", 1_000_000_000 ether)));
        nonTradeableToken = Token.wrap(address(new TestERC20Burnable("NONTRTKN", "NONTRTKN", 1_000_000_000 ether)));
        feeOnTransferToken = Token.wrap(address(new TestERC20FeeOnTransfer("FEETKN", "FEETKN", 1_000_000_000 ether)));

        // transfer tokens to user
        nonTradeableToken.safeTransfer(user1, MAX_SOURCE_AMOUNT * 2);
        feeOnTransferToken.safeTransfer(user1, MAX_SOURCE_AMOUNT * 2);
        token0.safeTransfer(user1, MAX_SOURCE_AMOUNT * 2);
        token1.safeTransfer(user1, MAX_SOURCE_AMOUNT * 2);
        token2.safeTransfer(user1, MAX_SOURCE_AMOUNT * 2);
        bnt.safeTransfer(user1, MAX_SOURCE_AMOUNT * 5);

        vm.stopPrank();
    }

    /**
     * @dev deploys carbon controller and voucher
     */
    function setupCarbonController() internal {
        // Deploy Voucher
        voucher = deployVoucher();

        // Deploy Carbon Controller
        carbonController = deployCarbonController(voucher);

        // setup contracts from admin
        vm.startPrank(admin);

        // Deploy new Carbon Controller to set proxy address in constructor
        address carbonControllerImpl = address(
            new TestCarbonController(IVoucher(address(voucher)), address(carbonController))
        );

        // Upgrade Carbon Controller to set proxy address in constructor
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(carbonController)), carbonControllerImpl);

        // Set Carbon Controller address
        carbonController = TestCarbonController(payable(address(carbonController)));

        // Grant minter role for voucher to carbon controller
        voucher.grantRole(voucher.roleMinter(), address(carbonController));

        vm.stopPrank();
    }

    /**
     * @dev deploys carbon vortex
     */
    function deployCarbonVortex(address _carbonController, address _bancorV3Mock) internal {
        // deploy contracts from admin
        vm.startPrank(admin);
        // Deploy Carbon Vortex
        carbonVortex = new CarbonVortex(bnt, ICarbonController(_carbonController), IBancorNetwork(_bancorV3Mock));
        bytes memory vortexInitData = abi.encodeWithSelector(carbonVortex.initialize.selector);
        // Deploy Carbon Vortex proxy
        address carbonVortexProxy = address(
            new OptimizedTransparentUpgradeableProxy(
                address(carbonVortex),
                payable(address(proxyAdmin)),
                vortexInitData
            )
        );

        // Set Carbon Vortex address
        carbonVortex = CarbonVortex(payable(carbonVortexProxy));

        // grant fee manager role to carbon vortex
        carbonController.grantRole(carbonController.roleFeesManager(), address(carbonVortex));

        vm.stopPrank();
    }

    /**
     * @dev deploys a new instance of the carbon controller
     */
    function deployCarbonController(TestVoucher _voucher) internal returns (TestCarbonController controller) {
        // deploy contracts from admin
        vm.startPrank(admin);
        // Deploy Carbon Controller
        TestCarbonController newCarbonController = new TestCarbonController(IVoucher(address(_voucher)), address(0));
        bytes memory carbonInitData = abi.encodeWithSelector(carbonController.initialize.selector);
        // Deploy Carbon proxy
        address carbonControllerProxy = address(
            new OptimizedTransparentUpgradeableProxy(
                address(newCarbonController),
                payable(address(proxyAdmin)),
                carbonInitData
            )
        );
        controller = TestCarbonController(payable(carbonControllerProxy));
        vm.stopPrank();
    }

    /**
     * @dev deploys a new instance of the voucher
     */
    function deployVoucher() internal returns (TestVoucher _voucher) {
        // deploy contracts from admin
        vm.startPrank(admin);
        // Deploy Voucher
        _voucher = new TestVoucher();
        bytes memory voucherInitData = abi.encodeWithSelector(voucher.initialize.selector, true, "ipfs://xxx", "");
        // Deploy Voucher proxy
        address voucherProxy = address(
            new OptimizedTransparentUpgradeableProxy(address(_voucher), payable(address(proxyAdmin)), voucherInitData)
        );
        _voucher = TestVoucher(voucherProxy);
        vm.stopPrank();
    }

    /**
     * @dev deploys carbon pol
     */
    function deployCarbonPOL(
        address _uniV3Router,
        address _uniV3Factory,
        address _uniV3Oracle,
        uint32 twapPeriod
    ) internal {
        // deploy contracts from admin
        vm.startPrank(admin);

        // Deploy Carbon POL
        carbonPOL = new CarbonPOL(
            ISwapRouter(_uniV3Router),
            IUniswapV3Factory(_uniV3Factory),
            IStaticOracle(_uniV3Oracle),
            weth,
            twapPeriod
        );

        bytes memory polInitData = abi.encodeWithSelector(carbonPOL.initialize.selector);
        // Deploy Carbon POL proxy
        address carbonPOLProxy = address(
            new OptimizedTransparentUpgradeableProxy(address(carbonPOL), payable(address(proxyAdmin)), polInitData)
        );

        // Set Carbon POL address
        carbonPOL = CarbonPOL(payable(carbonPOLProxy));

        vm.stopPrank();
    }

    function deployUniswapV3Factory() internal returns (MockUniswapV3Factory uniswapV3Factory) {
        // deploy contracts from admin
        vm.startPrank(admin);
        // deploy uniswap v3 factory mock
        uniswapV3Factory = new MockUniswapV3Factory();

        // create some test pools
        uniswapV3Factory.createPool(Token.unwrap(bnt), Token.unwrap(weth), 3000);
        uniswapV3Factory.createPool(Token.unwrap(token1), Token.unwrap(weth), 500);
        uniswapV3Factory.createPool(Token.unwrap(token1), Token.unwrap(weth), 3000);
        uniswapV3Factory.createPool(Token.unwrap(token2), Token.unwrap(weth), 3000);
        uniswapV3Factory.createPool(Token.unwrap(token1), Token.unwrap(NATIVE_TOKEN), 3000);

        vm.stopPrank();

        return uniswapV3Factory;
    }

    function deployUniswapV3Router(address _uniswapV3Factory) internal returns (MockUniswapV3Router uniswapV3Router) {
        // deploy contracts from admin
        vm.startPrank(admin);
        // deploy uniswap v3 router mock
        uniswapV3Router = new MockUniswapV3Router(300 ether, true, IUniswapV3Factory(_uniswapV3Factory));

        // send some tokens to uni v3 router
        nonTradeableToken.safeTransfer(address(uniswapV3Router), MAX_SOURCE_AMOUNT);
        token1.safeTransfer(address(uniswapV3Router), MAX_SOURCE_AMOUNT);
        token2.safeTransfer(address(uniswapV3Router), MAX_SOURCE_AMOUNT);
        bnt.safeTransfer(address(uniswapV3Router), MAX_SOURCE_AMOUNT * 5);
        // send eth to uni v3 router
        vm.deal(address(uniswapV3Router), MAX_SOURCE_AMOUNT);

        // mint weth to admin
        vm.deal(admin, MAX_SOURCE_AMOUNT * 5);
        IWETH(Token.unwrap(weth)).deposit{ value: MAX_SOURCE_AMOUNT * 5 }();
        // send weth to router
        weth.safeTransfer(address(uniswapV3Router), MAX_SOURCE_AMOUNT);

        vm.stopPrank();

        return uniswapV3Router;
    }

    function deployUniswapV3Oracle(address _uniswapV3Factory) internal returns (MockUniswapV3Oracle uniswapV3Oracle) {
        // deploy contracts from admin
        vm.startPrank(admin);
        // deploy uniswap v3 oracle mock
        uniswapV3Oracle = new MockUniswapV3Oracle(1e18, IUniswapV3Factory(_uniswapV3Factory));

        vm.stopPrank();

        return uniswapV3Oracle;
    }

    function deployBancorNetworkV3Mock() internal returns (MockBancorNetworkV3 bancorNetworkV3) {
        // deploy contracts from admin
        vm.startPrank(admin);
        // deploy bancor network v3 mock
        bancorNetworkV3 = new MockBancorNetworkV3(Token.unwrap(bnt), 300 ether, true);

        // send some tokens to bancor network v3
        nonTradeableToken.safeTransfer(address(bancorNetworkV3), MAX_SOURCE_AMOUNT);
        token1.safeTransfer(address(bancorNetworkV3), MAX_SOURCE_AMOUNT);
        token2.safeTransfer(address(bancorNetworkV3), MAX_SOURCE_AMOUNT);
        bnt.safeTransfer(address(bancorNetworkV3), MAX_SOURCE_AMOUNT * 5);
        // send eth to bancor network v3
        vm.deal(address(bancorNetworkV3), MAX_SOURCE_AMOUNT);

        // set pool collections for v3
        bancorNetworkV3.setCollectionByPool(bnt);
        bancorNetworkV3.setCollectionByPool(token1);
        bancorNetworkV3.setCollectionByPool(token2);
        bancorNetworkV3.setCollectionByPool(NATIVE_TOKEN);

        vm.stopPrank();

        return bancorNetworkV3;
    }

    function transferTokensToCarbonController() internal {
        vm.startPrank(admin);
        // transfer tokens
        nonTradeableToken.safeTransfer(address(carbonController), MAX_SOURCE_AMOUNT * 2);
        token1.safeTransfer(address(carbonController), MAX_SOURCE_AMOUNT * 2);
        token2.safeTransfer(address(carbonController), MAX_SOURCE_AMOUNT * 2);
        bnt.safeTransfer(address(carbonController), MAX_SOURCE_AMOUNT * 5);
        // transfer eth
        vm.deal(address(carbonController), MAX_SOURCE_AMOUNT);
        vm.stopPrank();
    }

    function transferTokensToCarbonPOL() internal {
        vm.startPrank(admin);
        // transfer tokens
        nonTradeableToken.safeTransfer(address(carbonPOL), MAX_SOURCE_AMOUNT * 2);
        token1.safeTransfer(address(carbonPOL), MAX_SOURCE_AMOUNT * 2);
        token2.safeTransfer(address(carbonPOL), MAX_SOURCE_AMOUNT * 2);
        bnt.safeTransfer(address(carbonPOL), MAX_SOURCE_AMOUNT * 5);
        vm.stopPrank();
    }
}
