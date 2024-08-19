// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { CarbonVortex } from "../../contracts/vortex/CarbonVortex.sol";
import { TestReenterCarbonVortex } from "../../contracts/helpers/TestReenterCarbonVortex.sol";
import { VortexTestCaseParser } from "./VortexTestCaseParser.t.sol";

import { AccessDenied, InvalidAddress, InvalidFee, ZeroValue } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";

import { ICarbonVortex } from "../../contracts/vortex/interfaces/ICarbonVortex.sol";
import { IVault } from "../../contracts/utility/interfaces/IVault.sol";

import { Token, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract CarbonVortexTest is TestFixture {
    using Address for address payable;

    address private vault;
    address private oldVortex;
    address payable private transferAddress;

    Token private targetToken;
    Token private finalTargetToken;

    // Test case parser helper
    VortexTestCaseParser private testCaseParser;

    uint32 private constant REWARDS_PPM_DEFAULT = 5000;
    uint32 private constant REWARDS_PPM_UPDATED = 7000;

    uint32 private constant PRICE_RESET_MULTIPLIER_DEFAULT = 2;
    uint32 private constant PRICE_RESET_MULTIPLIER_UPDATED = 3;

    uint32 private constant MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT = 4;
    uint32 private constant MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_UPDATED = 5;

    uint32 private constant PRICE_DECAY_HALFLIFE_DEFAULT = 12 hours;
    uint32 private constant PRICE_DECAY_HALFLIFE_UPDATED = 18 hours;

    uint32 private constant TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT = 10 days;
    uint32 private constant TARGET_TOKEN_PRICE_DECAY_HALFLIFE_UPDATED = 15 days;

    uint128 private constant MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT = 100 ether;
    uint128 private constant MAX_TARGET_TOKEN_SALE_AMOUNT_UPDATED = 150 ether;

    uint128 private constant MIN_TARGET_TOKEN_SALE_AMOUNT_DEFAULT = 10 ether;
    uint128 private constant MIN_TARGET_TOKEN_SALE_AMOUNT_UPDATED = 15 ether;

    uint128 private constant INITIAL_PRICE_SOURCE_AMOUNT = type(uint128).max;
    uint128 private constant INITIAL_PRICE_TARGET_AMOUNT = 1e12;

    uint256 private constant MAX_WITHDRAW_AMOUNT = 100_000_000 ether;

    // Events
    /**
     * @notice triggered when trading is reset for a token (dutch auction has been restarted)
     */
    event TradingReset(Token indexed token, ICarbonVortex.Price price);

    /**
     * @notice triggered after a successful trade is executed
     */
    event TokenTraded(address indexed caller, Token indexed token, uint128 sourceAmount, uint128 targetAmount);

    /**
     * @dev triggered when the rewards ppm are updated
     */
    event RewardsUpdated(uint32 prevRewardsPPM, uint32 newRewardsPPM);

    /**
     * @notice triggered when pair status is updated
     */
    event PairDisabledStatusUpdated(Token indexed token, bool prevStatus, bool newStatus);

    /**
     * @notice triggered after the price updates for a token
     */
    event PriceUpdated(Token indexed token, ICarbonVortex.Price price);

    /**
     * @dev triggered when tokens have been withdrawn by the admin
     */
    event FundsWithdrawn(Token[] indexed tokens, address indexed caller, address indexed target, uint256[] amounts);

    /**
     * @dev triggered when tokens have been withdrawn from the vault (Vault event)
     */
    event FundsWithdrawn(Token indexed token, address indexed caller, address indexed target, uint256 amount);

    /**
     * @notice triggered when the price reset multiplier is updated
     */
    event PriceResetMultiplierUpdated(uint32 prevPriceResetMultiplier, uint32 newPriceResetMultiplier);

    /**
     * @notice Triggered when the minimum token sale amount multiplier is updated
     */
    event MinTokenSaleAmountMultiplierUpdated(
        uint32 prevMinTokenSaleAmountMultiplier,
        uint32 newMinTokenSaleAmountMultiplier
    );

    /**
     * @notice triggered when the price decay halflife is updated (for all tokens except the target token)
     */
    event PriceDecayHalfLifeUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the price decay halflife is updated (for the target token only)
     */
    event TargetTokenPriceDecayHalfLifeUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the price decay halflife on price reset is updated (for the target token only)
     */
    event TargetTokenPriceDecayHalfLifeOnResetUpdated(uint32 prevPriceDecayHalfLife, uint32 newPriceDecayHalfLife);

    /**
     * @notice triggered when the target token sale amount is updated
     */
    event MaxTargetTokenSaleAmountUpdated(uint128 prevTargetTokenSaleAmount, uint128 newTargetTokenSaleAmount);

    /**
     * @notice triggered when the min token sale amount is updated
     */
    event MinTokenSaleAmountUpdated(Token indexed token, uint128 prevMinTokenSaleAmount, uint128 newMinTokenSaleAmount);

    /**
     * @dev triggered when fees are withdrawn (CarbonController event)
     */
    event FeesWithdrawn(Token indexed token, address indexed recipient, uint256 indexed amount, address sender);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
        // Deploy Vault
        vault = deployVault();
        // Deploy Old Vortex
        oldVortex = deployVault();
        // set up target token
        targetToken = NATIVE_TOKEN;
        // set up final target token
        finalTargetToken = bnt;
        // set up transfer address
        transferAddress = payable(user2);
        // Deploy Carbon Vortex
        deployCarbonVortex(address(carbonController), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        // Transfer tokens to Carbon Controller
        transferTokensToCarbonController();
        // Deploy test case parser
        testCaseParser = new VortexTestCaseParser();
    }

    /**
     * @dev construction tests
     */

    function testShouldRevertWhenDeployingWithInvalidTransferAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonVortex(carbonController, IVault(vault), IVault(oldVortex), payable(address(0)), NATIVE_TOKEN, bnt);
    }

    function testShouldRevertWhenDeployingWithInvalidTargetToken() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonVortex(
            carbonController,
            IVault(vault),
            IVault(oldVortex),
            transferAddress,
            Token.wrap(address(0)),
            bnt
        );
    }

    function testShouldBeInitialized() public view {
        uint16 version = carbonVortex.version();
        assertEq(version, 1);
    }

    function testShouldntBeAbleToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        carbonVortex.initialize();
    }

    /**
     * @dev rewards distribution tests
     */

    /// @dev test should distribute rewards to user on call to execute from carbon controller
    function testShouldDistributeRewardsToCallerOnExecuteFromCarbonController(
        uint256 i,
        uint256 feesAccumulated
    ) public {
        vm.startPrank(admin);

        i = bound(i, 0, 3);

        // pick one of these tokens to test
        Token[4] memory tokens = [token1, token2, targetToken, finalTargetToken];
        Token token = tokens[i];

        uint256 amount = bound(feesAccumulated, 0, MAX_WITHDRAW_AMOUNT);
        // set carbon controller fees and transfer tokens
        carbonController.testSetAccumulatedFees(token, amount);

        vm.stopPrank();

        vm.startPrank(user1);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256 balanceBefore = token.balanceOf(user1);

        Token[] memory tokensArr = new Token[](1);
        tokensArr[0] = token;
        uint256[] memory expectedUserRewards = new uint256[](1);
        expectedUserRewards[0] = (amount * rewards) / PPM_RESOLUTION;
        carbonVortex.execute(tokensArr);

        uint256 balanceAfter = token.balanceOf(user1);
        // assert user received his rewards
        assertEq(balanceAfter - balanceBefore, expectedUserRewards[0]);
    }

    /// @dev test should distribute rewards to caller on execute from vault and old vortex
    function testShouldDistributeRewardsToCallerOnExecuteFromVaultAndOldVortex(
        uint256 i,
        uint256 feesAccumulatedVault,
        uint256 feesAccumulatedOldVortex
    ) public {
        vm.startPrank(admin);

        // token index
        i = bound(i, 0, 3);

        // pick one of these tokens to test
        Token[4] memory tokens = [token1, token2, targetToken, finalTargetToken];
        Token token = tokens[i];

        feesAccumulatedVault = bound(feesAccumulatedVault, 0, MAX_WITHDRAW_AMOUNT);
        feesAccumulatedOldVortex = bound(feesAccumulatedOldVortex, 0, MAX_WITHDRAW_AMOUNT);
        // transfer tokens to vault and old vortex
        if (token == NATIVE_TOKEN) {
            vm.deal(address(vault), feesAccumulatedVault);
            vm.deal(address(oldVortex), feesAccumulatedOldVortex);
        } else {
            token.safeTransfer(address(vault), feesAccumulatedVault);
            token.safeTransfer(address(oldVortex), feesAccumulatedOldVortex);
        }

        // check combined token balance of both vault and old vortex
        uint256 balanceOfVault = token.balanceOf(address(vault));
        uint256 balanceOfOldVortex = token.balanceOf(address(oldVortex));
        uint256 combinedBalance = balanceOfVault + balanceOfOldVortex;

        vm.stopPrank();

        vm.startPrank(user1);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256 balanceBefore = token.balanceOf(user1);

        Token[] memory tokensArr = new Token[](1);
        tokensArr[0] = token;
        // calculate expected rewards
        uint256 expectedUserRewards = (combinedBalance * rewards) / PPM_RESOLUTION;
        carbonVortex.execute(tokensArr);

        uint256 balanceAfter = token.balanceOf(user1);
        // assert user received his rewards
        assertEq(balanceAfter - balanceBefore, expectedUserRewards);
    }

    /// @dev test should distribute rewards to user on call to execute from carbon controller for multiple tokens
    function testShouldDistributeRewardsToCallerOnExecuteFromCarbonControllerForMultipleTokens(
        uint256 feesAccumulated
    ) public {
        vm.startPrank(admin);
        uint256 amount = bound(feesAccumulated, 0, MAX_WITHDRAW_AMOUNT);
        // set carbon controller fees and transfer tokens
        carbonController.testSetAccumulatedFees(token1, amount);
        carbonController.testSetAccumulatedFees(token2, amount);
        carbonController.testSetAccumulatedFees(targetToken, amount);

        vm.stopPrank();

        vm.startPrank(user1);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256[3] memory balancesBefore = [
            token1.balanceOf(user1),
            token2.balanceOf(user1),
            targetToken.balanceOf(user1)
        ];

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = targetToken;
        uint256 expectedRewards = (amount * rewards) / PPM_RESOLUTION;
        carbonVortex.execute(tokens);

        uint256[3] memory balancesAfter = [
            token1.balanceOf(user1),
            token2.balanceOf(user1),
            targetToken.balanceOf(user1)
        ];

        // assert user received his rewards
        assertEq(balancesAfter[0] - balancesBefore[0], expectedRewards);
        assertEq(balancesAfter[1] - balancesBefore[1], expectedRewards);
        assertEq(balancesAfter[2] - balancesBefore[2], expectedRewards);
    }

    function testShouldDistributeRewardsToCallerOnExecuteFromOldVortexAndVaultForMultipleTokens(
        uint256 feesAccumulatedVault,
        uint256 feesAccumulatedOldVortex
    ) public {
        vm.startPrank(admin);
        feesAccumulatedVault = bound(feesAccumulatedVault, 0, MAX_WITHDRAW_AMOUNT);
        feesAccumulatedOldVortex = bound(feesAccumulatedOldVortex, 0, MAX_WITHDRAW_AMOUNT);
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = targetToken;
        // transfer tokens to vault and old vortex
        tokens[0].safeTransfer(address(vault), feesAccumulatedVault);
        tokens[0].safeTransfer(address(oldVortex), feesAccumulatedOldVortex);

        tokens[1].safeTransfer(address(vault), feesAccumulatedVault);
        tokens[1].safeTransfer(address(oldVortex), feesAccumulatedOldVortex);

        vm.deal(address(vault), feesAccumulatedVault);
        vm.deal(address(oldVortex), feesAccumulatedVault);

        uint256[3] memory balancesOfVault = [
            tokens[0].balanceOf(address(vault)),
            tokens[1].balanceOf(address(vault)),
            tokens[2].balanceOf(address(vault))
        ];
        uint256[3] memory balancesOfOldVortex = [
            tokens[0].balanceOf(address(oldVortex)),
            tokens[1].balanceOf(address(oldVortex)),
            tokens[2].balanceOf(address(oldVortex))
        ];
        uint256[3] memory combinedBalances = [
            balancesOfVault[0] + balancesOfOldVortex[0],
            balancesOfVault[1] + balancesOfOldVortex[1],
            balancesOfVault[2] + balancesOfOldVortex[2]
        ];

        vm.stopPrank();

        vm.startPrank(user1);

        uint256 rewards = carbonVortex.rewardsPPM();

        uint256[3] memory balancesBefore = [
            tokens[0].balanceOf(user1),
            tokens[1].balanceOf(user1),
            tokens[2].balanceOf(user1)
        ];

        // calculate expected rewards
        uint256[] memory expectedUserRewards = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            expectedUserRewards[i] = (combinedBalances[i] * rewards) / PPM_RESOLUTION;
        }

        // execute
        carbonVortex.execute(tokens);

        // assert user received his rewards
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(tokens[i].balanceOf(user1) - balancesBefore[i], expectedUserRewards[i]);
        }
    }

    /**
     * @dev execute function tests
     */

    // test should enable trading and start the dutch auction on execute
    function testShouldEnableTradingOnExecute() public {
        vm.startPrank(admin);

        // test with 3 tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = targetToken;

        uint256 accumulatedFees = 100 ether;

        // set fees in carbon controller
        carbonController.testSetAccumulatedFees(tokens[0], accumulatedFees);
        carbonController.testSetAccumulatedFees(tokens[1], accumulatedFees);
        carbonController.testSetAccumulatedFees(tokens[2], accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // get trading statuses before
        bool[3] memory tradingStatusBefore = [
            carbonVortex.tradingEnabled(tokens[0]),
            carbonVortex.tradingEnabled(tokens[1]),
            carbonVortex.tradingEnabled(tokens[2])
        ];

        // call execute for the tokens
        carbonVortex.execute(tokens);

        // get trading statuses after
        bool[3] memory tradingStatusAfter = [
            carbonVortex.tradingEnabled(tokens[0]),
            carbonVortex.tradingEnabled(tokens[1]),
            carbonVortex.tradingEnabled(tokens[2])
        ];

        for (uint256 i = 0; i < 3; ++i) {
            // assert trading is enabled
            assertTrue(tradingStatusAfter[i]);
            // assert trading statuses are updated
            assert(!tradingStatusBefore[i] && tradingStatusAfter[i]);
        }
    }

    /// @dev test should withdraw fees from CarbonController, Vault and OldVortex on calling execute
    function testShouldWithdrawFeesOnExecute() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](4);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;
        tokenAmounts[3] = 10 ether;
        Token[] memory tokens = new Token[](4);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = targetToken;
        tokens[3] = finalTargetToken;

        for (uint256 i = 0; i < 4; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], tokenAmounts[i]);
            tokens[i].safeTransfer(address(vault), tokenAmounts[i]);
            tokens[i].safeTransfer(address(oldVortex), tokenAmounts[i]);

            vm.expectEmit();
            // carbon controller fees event
            emit FeesWithdrawn(tokens[i], address(carbonVortex), tokenAmounts[i], address(carbonVortex));
            vm.expectEmit();
            // vault fees event
            emit FundsWithdrawn(tokens[i], address(carbonVortex), address(carbonVortex), tokenAmounts[i]);
            vm.expectEmit();
            // old vortex fees event
            emit FundsWithdrawn(tokens[i], address(carbonVortex), address(carbonVortex), tokenAmounts[i]);
            carbonVortex.execute(tokens);
        }
        vm.stopPrank();
    }

    /// @dev test that vortex can be deployed with carbon controller set to 0x0 address and it will be skipped on execute
    function testExecuteShouldSkipCarbonControllerDeployedWithZeroAddress() public {
        // deploy new vortex with carbon controller set to 0x0
        deployCarbonVortex(address(0), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        vm.startPrank(admin);

        // test with the target token
        Token token = targetToken;

        uint256 accumulatedFees = 100 ether;

        // send fees to vault
        token.safeTransfer(address(vault), accumulatedFees);
        // send tokens to old vortex
        token.safeTransfer(address(oldVortex), accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // call execute for the target token
        // expect two withdraw emits from vault and old vortex
        for (uint256 i = 0; i < 2; ++i) {
            vm.expectEmit();
            emit FundsWithdrawn(token, address(carbonVortex), address(carbonVortex), accumulatedFees);
        }
        carbonVortex.execute(tokens);
    }

    /// @dev test that vortex can be deployed with vault set to 0x0 address and it will be skipped on execute
    function testExecuteShouldSkipVaultWithZeroAddress() public {
        // deploy vortex with a vault with 0x0 address
        deployCarbonVortex(
            address(carbonController),
            address(0),
            oldVortex,
            transferAddress,
            targetToken,
            finalTargetToken
        );

        vm.startPrank(admin);

        // test with the target token
        Token token = targetToken;

        uint256 accumulatedFees = 100 ether;

        // send fees to old vortex
        token.safeTransfer(address(oldVortex), accumulatedFees);

        // accumulate fees in carbon controller
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // call execute for the target token
        // expect two withdraw emits from carbon controller and old vortex
        vm.expectEmit();
        emit FeesWithdrawn(token, address(carbonVortex), accumulatedFees, address(carbonVortex));
        vm.expectEmit();
        emit FundsWithdrawn(token, address(carbonVortex), address(carbonVortex), accumulatedFees);
        // execute
        carbonVortex.execute(tokens);
    }

    /// @dev test that vortex can be deployed with old vortex set to 0x0 address and it will be skipped on execute
    function testExecuteShouldSkipOldVortexWithZeroAddress() public {
        // deploy vortex with a old vortex with 0x0 address
        deployCarbonVortex(
            address(carbonController),
            vault,
            address(0),
            transferAddress,
            targetToken,
            finalTargetToken
        );

        vm.startPrank(admin);

        // test with the target token
        Token token = targetToken;

        uint256 accumulatedFees = 100 ether;

        // send fees to vault
        token.safeTransfer(address(vault), accumulatedFees);

        // accumulate fees in carbon controller
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // call execute for the target token
        // expect two withdraw emits from carbon controller and old vortex
        vm.expectEmit();
        emit FeesWithdrawn(token, address(carbonVortex), accumulatedFees, address(carbonVortex));
        vm.expectEmit();
        emit FundsWithdrawn(token, address(carbonVortex), address(carbonVortex), accumulatedFees);
        // execute
        carbonVortex.execute(tokens);
    }

    /**
     * @dev token transfers on execute tests
     */

    /// @dev test should properly transfer out fees from the vaults and send fees to the vortex
    /// @param idx: token index
    /// @param feesAccumulated: fees accumulated in the carbon controller, vault and old vortex
    function testShouldProperlyTransferAmountsOnExecuteForToken(uint256 idx, uint256[3] memory feesAccumulated) public {
        vm.startPrank(admin);

        // token index
        idx = bound(idx, 0, 2);

        // pick one of these tokens to test
        Token[3] memory tokens = [token1, token2, targetToken];
        Token token = tokens[idx];

        // set fee amounts
        for (uint256 i = 0; i < 3; ++i) {
            feesAccumulated[i] = bound(feesAccumulated[i], 0, MAX_WITHDRAW_AMOUNT);
        }

        // set token fees in the carbon controller
        carbonController.testSetAccumulatedFees(token, feesAccumulated[0]);

        // transfer tokens to vault and old vortex
        if (token == NATIVE_TOKEN) {
            vm.deal(address(vault), feesAccumulated[1]);
            vm.deal(address(oldVortex), feesAccumulated[2]);
        } else {
            token.safeTransfer(address(vault), feesAccumulated[1]);
            token.safeTransfer(address(oldVortex), feesAccumulated[2]);
        }

        vm.stopPrank();

        vm.startPrank(user1);

        uint256[4] memory balancesBefore = [
            token.balanceOf(address(carbonController)),
            token.balanceOf(address(vault)),
            token.balanceOf(address(oldVortex)),
            token.balanceOf(address(carbonVortex))
        ];

        Token[] memory tokensArr = new Token[](1);
        tokensArr[0] = token;
        carbonVortex.execute(tokensArr);

        uint256[4] memory balancesAfter = [
            token.balanceOf(address(carbonController)),
            token.balanceOf(address(vault)),
            token.balanceOf(address(oldVortex)),
            token.balanceOf(address(carbonVortex))
        ];

        // assert full carbon controller, vault and old vortex fees are withdrawn
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(balancesBefore[i] - balancesAfter[i], feesAccumulated[i]);
        }

        // assert full fees are transferred to the vortex
        uint256 totalFeesAccumulated = feesAccumulated[0] + feesAccumulated[1] + feesAccumulated[2];
        uint256 expectedRewards = (totalFeesAccumulated * carbonVortex.rewardsPPM()) / PPM_RESOLUTION;
        assertEq(balancesAfter[3] - balancesBefore[3], totalFeesAccumulated - expectedRewards);
    }

    /// @dev test should properly transfer out fees from the vaults and send fees to the vortex for multiple tokens
    function testShouldProperlyTransferAmountsOnExecuteForMultipleTokens(uint256[3] memory feesAccumulated) public {
        vm.startPrank(admin);

        // test with these 3 tokens
        Token[3] memory tokens = [token1, token2, targetToken];

        // set fee amounts
        for (uint256 i = 0; i < 3; ++i) {
            feesAccumulated[i] = bound(feesAccumulated[i], 0, MAX_WITHDRAW_AMOUNT);
        }

        // set token fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], feesAccumulated[0]);
        }

        // transfer tokens to vault and old vortex
        vm.deal(address(vault), feesAccumulated[1]);
        vm.deal(address(oldVortex), feesAccumulated[2]);
        for (uint256 i = 0; i < 2; ++i) {
            tokens[i].safeTransfer(address(vault), feesAccumulated[1]);
            tokens[i].safeTransfer(address(oldVortex), feesAccumulated[2]);
        }

        vm.stopPrank();

        vm.startPrank(user1);

        uint256[4][3] memory balancesBefore = [
            [
                tokens[0].balanceOf(address(carbonController)),
                tokens[0].balanceOf(address(vault)),
                tokens[0].balanceOf(address(oldVortex)),
                tokens[0].balanceOf(address(carbonVortex))
            ],
            [
                tokens[1].balanceOf(address(carbonController)),
                tokens[1].balanceOf(address(vault)),
                tokens[1].balanceOf(address(oldVortex)),
                tokens[1].balanceOf(address(carbonVortex))
            ],
            [
                tokens[2].balanceOf(address(carbonController)),
                tokens[2].balanceOf(address(vault)),
                tokens[2].balanceOf(address(oldVortex)),
                tokens[2].balanceOf(address(carbonVortex))
            ]
        ];

        Token[] memory tokensArr = new Token[](3);
        for (uint256 i = 0; i < 3; ++i) {
            tokensArr[i] = tokens[i];
        }

        carbonVortex.execute(tokensArr);

        uint256[4][3] memory balancesAfter = [
            [
                tokens[0].balanceOf(address(carbonController)),
                tokens[0].balanceOf(address(vault)),
                tokens[0].balanceOf(address(oldVortex)),
                tokens[0].balanceOf(address(carbonVortex))
            ],
            [
                tokens[1].balanceOf(address(carbonController)),
                tokens[1].balanceOf(address(vault)),
                tokens[1].balanceOf(address(oldVortex)),
                tokens[1].balanceOf(address(carbonVortex))
            ],
            [
                tokens[2].balanceOf(address(carbonController)),
                tokens[2].balanceOf(address(vault)),
                tokens[2].balanceOf(address(oldVortex)),
                tokens[2].balanceOf(address(carbonVortex))
            ]
        ];

        // assert full carbon controller, vault and old vortex fees are withdrawn
        for (uint256 i = 0; i < 3; ++i) {
            for (uint256 j = 0; j < 3; ++j) {
                assertEq(balancesBefore[i][j] - balancesAfter[i][j], feesAccumulated[j]);
            }
        }

        // assert full fees are transferred to the vortex
        uint256 totalFeesAccumulated = feesAccumulated[0] + feesAccumulated[1] + feesAccumulated[2];
        uint256 expectedRewards = (totalFeesAccumulated * carbonVortex.rewardsPPM()) / PPM_RESOLUTION;
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(balancesAfter[i][3] - balancesBefore[i][3], totalFeesAccumulated - expectedRewards);
        }
    }

    /// @dev test execute shouldnt emit a trade reset event for the target token if the final target token is zero
    function testShouldTransferTokensDirectlyToTheTransferAddressOnExecuteIfFinalTargetTokenIsZero() public {
        // Deploy new Carbon Vortex with the final target token set to the zero address
        deployCarbonVortex(
            address(carbonController),
            vault,
            oldVortex,
            transferAddress,
            targetToken,
            Token.wrap(address(0))
        );

        vm.startPrank(admin);

        // test with the target token
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;

        uint256 accumulatedFees = 100 ether;

        // set fees in carbon controller
        carbonController.testSetAccumulatedFees(tokens[0], accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // get transfer address balance before
        uint256 balanceBefore = targetToken.balanceOf(transferAddress);

        // call execute for the target token
        carbonVortex.execute(tokens);

        // get transfer address balance after
        uint256 balanceAfter = targetToken.balanceOf(transferAddress);

        // calculate reward amount
        uint256 rewardAmount = (accumulatedFees * carbonVortex.rewardsPPM()) / PPM_RESOLUTION;

        // assert receiver address received the fees
        assertEq(balanceAfter - balanceBefore, accumulatedFees - rewardAmount);
    }

    /// @dev test execute should increment total collected on execute for the target token if the final target token is zero
    function testShouldIncrementTotalCollectedOnExecuteIfFinalTargetTokenAddressIsZero() public {
        // Deploy new Carbon Vortex with the final target token set to the zero address
        deployCarbonVortex(
            address(carbonController),
            vault,
            oldVortex,
            transferAddress,
            targetToken,
            Token.wrap(address(0))
        );

        vm.startPrank(admin);

        // test with the target token
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;

        uint256 accumulatedFees = 100 ether;

        // set fees in carbon controller
        carbonController.testSetAccumulatedFees(tokens[0], accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // get total collected balance before
        uint256 totalCollectedBefore = carbonVortex.totalCollected();

        // call execute for the target token
        carbonVortex.execute(tokens);

        // get total collected balance after
        uint256 totalCollectedAfter = carbonVortex.totalCollected();

        // calculate reward amount
        uint256 rewardAmount = (accumulatedFees * carbonVortex.rewardsPPM()) / PPM_RESOLUTION;

        // assert receiver address received the fees
        assertEq(totalCollectedAfter - totalCollectedBefore, accumulatedFees - rewardAmount);
    }

    /// @dev test execute should update the current sale amount on first call to execute for the target token
    function testShouldUpdateTheCurrentSaleAmountOnFirstCallToExecuteForTheTargetToken(uint256 accumulatedFees) public {
        vm.startPrank(admin);

        // test with the target token
        Token token = targetToken;

        accumulatedFees = bound(accumulatedFees, 0, MAX_WITHDRAW_AMOUNT);

        // set fees in the carbon controller
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;

        // check current trade amount
        uint128 currentTradeAmount = carbonVortex.targetTokenSaleAmount().current;
        // expect amount to be 0
        assertEq(currentTradeAmount, 0);

        carbonVortex.execute(tokens);

        // check current trade amount
        currentTradeAmount = carbonVortex.targetTokenSaleAmount().current;

        // check expected rewards
        uint128 expectedReward = uint128((carbonVortex.rewardsPPM() * accumulatedFees) / PPM_RESOLUTION);
        // calculate the target token sale amount
        uint128 expectedTradeAmount = uint128(accumulatedFees - expectedReward);

        // expect amount to be the accumulated fees or the max trade amount
        assertEq(currentTradeAmount, Math.min(expectedTradeAmount, MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT));
    }

    /// @dev test calling execute for the final target token shouldn't enable trading for it
    /// @dev reasoning is only finalTarget -> targetToken trading is enabled
    function testExecuteForTheFinalTargetTokenShouldntEnableTrading() public {
        vm.startPrank(admin);

        // increase fees for the finalTarget
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(finalTargetToken, accumulatedFees);

        Token[] memory tokens = new Token[](1);
        tokens[0] = finalTargetToken;

        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // check trading for the finalTarget token is not enabled
        assertEq(carbonVortex.tradingEnabled(finalTargetToken), false);
    }

    /**
     * @dev Execute event emit tests
     */

    /// @dev test execute should emit a TradeReset event on first call to execute for the target token
    function testShouldEmitTradeResetEventOnFirstCallToExecuteForTheTargetToken() public {
        vm.startPrank(admin);

        // test with the target token
        Token token = targetToken;

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;

        // test should emit TradingReset event with proper price
        vm.expectEmit();
        emit TradingReset(token, price);
        carbonVortex.execute(tokens);
    }

    /// @dev test execute should emit a TradeReset event on first call to execute for each token
    function testShouldEmitTradeResetEventOnFirstCallToExecuteForEachToken() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], accumulatedFees);
        }
        // transfer token0 fees to carbon
        token0.safeTransfer(address(carbonController), accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        // test should emit TradingReset event for each token in the correct order
        for (uint256 i = 0; i < 3; ++i) {
            vm.expectEmit();
            emit TradingReset(tokens[i], price);
        }
        carbonVortex.execute(tokens);
    }

    /// @dev test execute should emit a TradeReset event on subsequent calls to execute if the amounts exceed the min sale amount
    function testShouldEmitTradeResetEventOnSecondCallToExecuteIfExceedsMinSaleAmountForEachToken() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], accumulatedFees);
        }
        // transfer token0 fees to carbon
        token0.safeTransfer(address(carbonController), accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });
        carbonVortex.execute(tokens);

        // prank admin and increase fees
        vm.startPrank(admin);
        // get min sale amount multiplier
        uint32 minTokenSaleAmountMultiplier = carbonVortex.minTokenSaleAmountMultiplier();
        // get min sale amount for each token
        uint128[] memory minSaleAmounts = new uint128[](3);
        for (uint256 i = 0; i < 3; ++i) {
            minSaleAmounts[i] = carbonVortex.minTokenSaleAmount(tokens[i]);
        }
        // set fees again
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], minSaleAmounts[i] * minTokenSaleAmountMultiplier + 1);
        }
        // transfer token0 fees to carbon
        token0.safeTransfer(address(carbonController), minSaleAmounts[0] * minTokenSaleAmountMultiplier + 1);

        vm.stopPrank();

        vm.startPrank(user1);

        // test should emit TradingReset event for each token in the correct order
        for (uint256 i = 0; i < 3; ++i) {
            vm.expectEmit();
            emit TradingReset(tokens[i], price);
        }
        carbonVortex.execute(tokens);
    }

    /// @dev test execute should emit a MinSaleAmountUpdated event on first call to execute for each token
    function testShouldEmitMinTokenSaleAmountUpdatedEventOnFirstCallToExecuteForEachToken() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], accumulatedFees);
        }
        // transfer token0 fees to carbon
        token0.safeTransfer(address(carbonController), accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        uint128 expectedReward = uint128((carbonVortex.rewardsPPM() * accumulatedFees) / PPM_RESOLUTION);

        // test should emit MinTokenSaleAmountUpdated event for each token in the correct order
        for (uint256 i = 0; i < 3; ++i) {
            vm.expectEmit();
            emit MinTokenSaleAmountUpdated({
                token: tokens[i],
                prevMinTokenSaleAmount: 0,
                newMinTokenSaleAmount: uint128(accumulatedFees - expectedReward) / 2
            });
        }
        carbonVortex.execute(tokens);
    }

    /// @dev test shouldn't emit a trade reset event on execute for tokens which have no fees accumulated
    function testFailShouldntEmitTradeResetForTokensWhichHaveNoFeesAccumulated() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;

        uint256 accumulatedFees = 100 ether;

        // set fees for token0 and token2 in the carbon controller
        carbonController.testSetAccumulatedFees(tokens[0], accumulatedFees);
        carbonController.testSetAccumulatedFees(tokens[2], accumulatedFees);
        // transfer token0 fees to carbon
        tokens[0].safeTransfer(address(carbonController), accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        // test shouldn't emit TradingReset event for token1
        vm.expectEmit();
        emit TradingReset(tokens[1], price);
        carbonVortex.execute(tokens);
    }

    /// @dev test shouldn't emit a trade reset on execute for tokens which are disabled
    function testFailShouldntEmitTradeResetForTokensWhichAreDisabled() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], accumulatedFees);
        }
        // transfer token0 fees to carbon
        token0.safeTransfer(address(carbonController), accumulatedFees);

        // disable token1
        carbonVortex.disablePair(tokens[1], true);

        vm.stopPrank();

        vm.startPrank(user1);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        // test shouldn't emit TradingReset event for token1
        vm.expectEmit();
        emit TradingReset(tokens[1], price);
        carbonVortex.execute(tokens);
    }

    /// @dev test execute shouldnt emit a trade reset event for the target token if the final target token is zero
    function testFailShouldntEmitTradeResetForTheTargetTokenIfTheFinalTargetTokenIsZero() public {
        // Deploy new Carbon Vortex with the final target token set to the zero address
        deployCarbonVortex(
            address(carbonController),
            vault,
            oldVortex,
            transferAddress,
            targetToken,
            Token.wrap(address(0))
        );

        vm.startPrank(admin);

        // test with the target token
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;

        uint256 accumulatedFees = 100 ether;

        // set fees in carbon controller
        carbonController.testSetAccumulatedFees(tokens[0], accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        // test shouldn't emit TradingReset event for the target token
        vm.expectEmit();
        emit TradingReset(targetToken, price);
        carbonVortex.execute(tokens);
    }

    function testShouldRevertOnExecuteIfNoTokensArePassed() public {
        Token[] memory tokens = new Token[](0);

        vm.startPrank(user1);

        // test should revert
        vm.expectRevert(ICarbonVortex.InvalidTokenLength.selector);
        carbonVortex.execute(tokens);
    }

    function testShouldRevertOnExecuteIfAnyOfTheTokensPassedIsTheZeroAddress() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = Token.wrap(address(0));

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], accumulatedFees);
        }

        vm.stopPrank();

        vm.startPrank(user1);

        // test should revert
        vm.expectRevert(ICarbonVortex.InvalidToken.selector);
        carbonVortex.execute(tokens);
    }

    function testShouldRevertOnExecuteIfThereAreDuplicateTokens() public {
        vm.startPrank(admin);

        // test with these three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token0;
        tokens[2] = token2;

        uint256 accumulatedFees = 100 ether;

        // set fees in the carbon controller
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], accumulatedFees);
        }
        // transfer token0 fees to carbon
        token0.safeTransfer(address(carbonController), accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // test should revert
        vm.expectRevert(ICarbonVortex.DuplicateToken.selector);
        carbonVortex.execute(tokens);
    }

    /**
     * @dev trade tests
     */

    /// @dev test that user should be able to trade final target token for target token
    function testUserShouldBeAbleToTradeTargetForFinalTarget() public {
        // execute so that trading can start for the target token

        vm.startPrank(admin);

        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.stopPrank();

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1 ether;

        uint256 targetBalanceBeforeVortex = targetToken.balanceOf(address(carbonVortex));
        uint256 targetBalanceBeforeUser = targetToken.balanceOf(user1);
        uint256 finalTargetBalanceBeforeVortex = finalTargetToken.balanceOf(address(carbonVortex));
        uint256 finalTargetBalanceBeforeUser = finalTargetToken.balanceOf(user1);

        // advance time so that the price decays and gets to market price
        // market price = 4000 BNT per 1 ETH - 38.5 days
        vm.warp(64 days);

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(targetToken, targetAmount);

        // approve the source token
        finalTargetToken.safeApprove(address(carbonVortex), expectedSourceAmount);
        // trade
        carbonVortex.trade(targetToken, targetAmount, expectedSourceAmount);

        uint256 targetBalanceAfterVortex = targetToken.balanceOf(address(carbonVortex));
        uint256 targetBalanceAfterUser = targetToken.balanceOf(user1);
        uint256 finalTargetBalanceAfterUser = finalTargetToken.balanceOf(user1);
        uint256 finalTargetBalanceAfterVortex = finalTargetToken.balanceOf(address(carbonVortex));

        // assert vortex target token balance changed
        assertEq(targetBalanceBeforeVortex - targetBalanceAfterVortex, targetAmount);

        // vortex final target token balance should remain the same because token gets transferred to the transfer address
        assertEq(finalTargetBalanceBeforeVortex - finalTargetBalanceAfterVortex, 0);

        // assert user target / final target token balances changed
        assertEq(targetBalanceAfterUser - targetBalanceBeforeUser, targetAmount);
        assertEq(finalTargetBalanceBeforeUser - finalTargetBalanceAfterUser, expectedSourceAmount);
    }

    function testShouldTransferFundsToTransferAddressAtEndOfFinalTargetToTargetTokenTrade() public {
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1 ether;

        uint256 finalTargetBalanceBefore = finalTargetToken.balanceOf(transferAddress);

        // advance time so that the price decays and gets to market price
        // market price = 4000 BNT per 1 ETH - 38.5 days
        vm.warp(39 days);

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(targetToken, targetAmount);

        // approve the source token
        finalTargetToken.safeApprove(address(carbonVortex), expectedSourceAmount);
        // trade
        carbonVortex.trade(targetToken, targetAmount, expectedSourceAmount);

        uint256 finalTargetBalanceAfter = finalTargetToken.balanceOf(transferAddress);

        uint256 balanceGain = finalTargetBalanceAfter - finalTargetBalanceBefore;

        // assert that `transferAddress` received the final target token
        assertEq(balanceGain, expectedSourceAmount);
    }

    function testTradingTargetTokenForTokenShouldSendTokenBalanceToTheUser() public {
        vm.prank(admin);
        Token token = token1;
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute so that the vortex has tokens
        carbonVortex.execute(tokens);

        // increase timestamp so that the token is tradeable
        vm.warp(46 days);

        uint256 balanceBefore = token.balanceOf(user1);

        uint128 targetAmount = 1 ether;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, targetAmount);

        // trade (send sourceAmount of native token because the target token is native)
        carbonVortex.trade{ value: sourceAmount }(token, targetAmount, sourceAmount);

        uint256 balanceAfter = token.balanceOf(user1);

        uint256 balanceGain = balanceAfter - balanceBefore;

        assertEq(balanceGain, targetAmount);
    }

    function testTradingTargetTokenForTokenShouldIncreaseVortexTargetTokenBalance() public {
        vm.prank(admin);
        Token token = token1;
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute so that the vortex has tokens
        carbonVortex.execute(tokens);

        // increase timestamp so that the token is tradeable
        vm.warp(46 days);

        uint256 balanceBefore = targetToken.balanceOf(address(carbonVortex));

        uint128 targetAmount = 1 ether;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, targetAmount);

        // trade (send sourceAmount of native token because the target token is native)
        carbonVortex.trade{ value: sourceAmount }(token, targetAmount, sourceAmount);

        uint256 balanceAfter = targetToken.balanceOf(address(carbonVortex));

        uint256 balanceGain = balanceAfter - balanceBefore;

        assertEq(balanceGain, sourceAmount);
    }

    function testTradingTargetTokenForTokenShouldResetTheAuctionIfBelowTheMinSaleAmount() public {
        vm.prank(admin);
        Token token = token1;
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute so that the vortex has tokens
        carbonVortex.execute(tokens);

        // increase timestamp so that the token is tradeable
        vm.warp(46 days);

        uint128 minSaleAmount = carbonVortex.minTokenSaleAmount(token);

        uint128 amountAvailableForTrading = carbonVortex.amountAvailableForTrading(token);

        uint128 tradeAmountToResetTheMinSale = amountAvailableForTrading + 1 - minSaleAmount;

        // get target amount
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, tradeAmountToResetTheMinSale);

        ICarbonVortex.Price memory initialPrice = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        // expect trading reset event to be emitted
        vm.expectEmit();
        emit TradingReset(token, initialPrice);
        carbonVortex.trade{ value: sourceAmount }(token, tradeAmountToResetTheMinSale, sourceAmount);

        // check price has been reset to initial
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);

        assertEq(price.sourceAmount, initialPrice.sourceAmount);
        assertEq(price.targetAmount, initialPrice.targetAmount);
    }

    /// @dev test that on target -> token trade the target token auction is reset:
    /// @dev if the target token amount available for trading is below the min sale amount / minTokenSaleAmountMultiplier
    /// @dev before the trade, regardless of the token amount traded (top ups for target token don't affect the behavior)
    function testTradingTargetTokenForTokenShouldResetTheTargetTokenAuctionIfBelowTheMinSaleAmount() public {
        vm.prank(admin);
        Token token = token1;
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](2);
        tokens[0] = token;
        tokens[1] = targetToken;
        // execute so that the vortex has tokens
        carbonVortex.execute(tokens);

        // increase timestamp so that the token is tradeable
        vm.warp(46 days);

        uint128 minSaleAmount = carbonVortex.minTokenSaleAmount(targetToken);

        uint128 amountAvailableForTrading = carbonVortex.amountAvailableForTrading(targetToken);

        uint128 minTokenSaleAmount = carbonVortex.minTokenSaleAmount(targetToken);
        uint32 minTokenSaleAmountMultiplier = carbonVortex.minTokenSaleAmountMultiplier();

        // we need to sell at least minSaleAmount / minTokenSaleAmountMultiplier
        uint128 tradeAmountToResetTheMinSale = amountAvailableForTrading +
            1e18 -
            minSaleAmount /
            minTokenSaleAmountMultiplier;

        // get source amount for final target -> target trade
        uint128 sourceAmountFirstTrade = carbonVortex.expectedTradeInput(targetToken, tradeAmountToResetTheMinSale);

        // approve final target token
        finalTargetToken.safeApprove(address(carbonVortex), sourceAmountFirstTrade);
        carbonVortex.trade(targetToken, tradeAmountToResetTheMinSale, sourceAmountFirstTrade);

        uint128 availableTargetTokenForTrading = carbonVortex.amountAvailableForTrading(targetToken);
        // assert target token left is less than min sale amount / multiplier
        assertLt(availableTargetTokenForTrading, minTokenSaleAmount / minTokenSaleAmountMultiplier);

        // perform a target -> token trade to reset the target token auction

        // get target amount
        uint128 tradeAmount = 10 ether;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, tradeAmount);

        ICarbonVortex.Price memory initialPrice = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        // expect trading reset for the target token event to be emitted
        vm.expectEmit();
        emit TradingReset(targetToken, initialPrice);
        carbonVortex.trade{ value: sourceAmount }(token, tradeAmount, sourceAmount);

        // check price has been reset to initial
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(targetToken);

        assertEq(price.sourceAmount, initialPrice.sourceAmount);
        assertEq(price.targetAmount, initialPrice.targetAmount);
    }

    /// @dev test trading target token for token should refund any excess native token sent to the user
    function testTradingTargetTokenForTokenShouldRefundExcessNativeTokenSentToUser() public {
        vm.prank(admin);
        Token token = token1;
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute so that the vortex has tokens
        carbonVortex.execute(tokens);

        // increase timestamp so that the token is tradeable
        vm.warp(46 days);

        uint128 targetAmount = 1 ether;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, targetAmount);

        uint256 balanceBefore = address(user1).balance;

        // trade (send sourceAmount of native token because the target token is native)
        carbonVortex.trade{ value: sourceAmount + 1 }(token, targetAmount, sourceAmount);

        uint256 balanceAfter = address(user1).balance;

        uint256 balanceSent = balanceBefore - balanceAfter;

        assertEq(balanceSent, sourceAmount);
    }

    /// @dev test trading target token for token should transfer target tokens to
    /// @dev transfer address if the final target token is zero
    function testTradingTargetTokenForTokenShouldTransferTargetTokensToTransferAddressIfFinalTargetTokenIsZero()
        public
    {
        // Deploy new Carbon Vortex with the final target token set to the zero address
        deployCarbonVortex(
            address(carbonController),
            vault,
            oldVortex,
            transferAddress,
            targetToken,
            Token.wrap(address(0))
        );

        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token1, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        // execute so that the vortex has tokens
        carbonVortex.execute(tokens);

        // increase timestamp so that the token is tradeable
        vm.warp(46 days);

        uint128 targetAmount = 1 ether;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token1, targetAmount);

        uint256 balanceBefore = targetToken.balanceOf(transferAddress);

        // trade (send sourceAmount of native token because the target token is native)
        carbonVortex.trade{ value: sourceAmount }(token1, targetAmount, sourceAmount);

        uint256 balanceAfter = targetToken.balanceOf(transferAddress);

        uint256 balanceGain = balanceAfter - balanceBefore;

        assertEq(balanceGain, sourceAmount);
    }

    /// @dev test that sending any ETH with the transaction
    /// @dev on target -> token trades should revert if targetToken != NATIVE_TOKEN
    function testShouldRevertIfUnnecessaryNativeTokenSentOnTargetToFinalTargetTrades() public {
        targetToken = bnt;
        finalTargetToken = NATIVE_TOKEN;
        Token token = token1;
        // Deploy new Carbon Vortex with the target token set to a token different than native token
        deployCarbonVortex(address(carbonController), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, targetAmount);

        // advance time
        vm.warp(45 days);

        // trade
        vm.expectRevert(ICarbonVortex.UnnecessaryNativeTokenReceived.selector);
        carbonVortex.trade{ value: 1 }(token, targetAmount, sourceAmount);
    }

    /// @dev test that sending any ETH with the transaction
    /// @dev on final target -> target token trades should revert if finalTargetToken != NATIVE_TOKEN
    function testShouldRevertIfUnnecessaryNativeTokenSentOnFinalTargetToTargetTrades() public {
        Token token = targetToken;
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, targetAmount);

        // advance time
        vm.warp(45 days);

        // trade
        vm.expectRevert(ICarbonVortex.UnnecessaryNativeTokenReceived.selector);
        carbonVortex.trade{ value: 1 }(token, targetAmount, sourceAmount);
    }

    /// @dev test that sending less than the sourceAmount of ETH with the transaction
    /// @dev on final target -> target token trades should revert if finalTarget == NATIVE_TOKEN
    function testShouldRevertIfInsufficientNativeTokenSentOnFinalTargetToTargetTokenTrade() public {
        targetToken = bnt;
        finalTargetToken = NATIVE_TOKEN;
        // Deploy new Carbon Vortex with the final target token set to the native token
        deployCarbonVortex(address(carbonController), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1 ether;

        // advance time
        vm.warp(45 days);

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(targetToken, targetAmount);

        // trade
        vm.expectRevert(ICarbonVortex.InsufficientNativeTokenSent.selector);
        carbonVortex.trade{ value: expectedSourceAmount - 1 }(bnt, targetAmount, expectedSourceAmount);
    }

    /// @dev test that if the final target token is the native token,
    /// @dev on finalTarget -> target trade the tokens will be transferred directly to transferAddress
    function testShouldTransferTokensDirectlyToTransferAddressOnFinalTargetToTargetTokenTrade() public {
        targetToken = bnt;
        finalTargetToken = NATIVE_TOKEN;
        // Deploy new Carbon Vortex with the final target token set to the native token
        deployCarbonVortex(address(carbonController), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1 ether;

        // advance time
        vm.warp(45 days);

        // get transfer address balance before
        uint256 balanceBefore = transferAddress.balance;

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(targetToken, targetAmount);

        // trade
        carbonVortex.trade{ value: expectedSourceAmount }(targetToken, targetAmount, expectedSourceAmount);

        // get transfer address balance after
        uint256 balanceAfter = transferAddress.balance;

        // get balance gain
        uint256 balanceGain = balanceAfter - balanceBefore;

        // assert transfer address received the final target token
        assertEq(balanceGain, expectedSourceAmount);
    }

    /// @dev test that if the finalTarget token is the native token, on finalTarget -> target token trades
    /// @dev user should be refunded any excess native token sent
    function testShouldRefundExcessNativeTokenSentOnFinalTargetToTargetTokenTrade() public {
        targetToken = bnt;
        finalTargetToken = NATIVE_TOKEN;
        // Deploy new Carbon Vortex with the final target token set to the native token
        deployCarbonVortex(address(carbonController), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // trade target for final target
        uint128 targetAmount = 1 ether;

        // advance time
        vm.warp(45 days);

        // get transfer address balance before
        uint256 balanceBefore = address(user1).balance;

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(targetToken, targetAmount);

        // trade
        carbonVortex.trade{ value: expectedSourceAmount + 1 }(targetToken, targetAmount, expectedSourceAmount);

        // get transfer address balance after
        uint256 balanceAfter = address(user1).balance;

        // get balance sent
        uint256 balanceSent = balanceBefore - balanceAfter;

        // assert user received the excess native token
        assertEq(balanceSent, expectedSourceAmount);
    }

    /// @dev test should revert if user hasn't sent enough target tokens for trade
    function testShouldRevertIfUserHasntSentEnoughTargetTokenForTrade() public {
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token1, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        carbonVortex.execute(tokens);

        // trade target token for token1
        uint128 targetAmount = 1 ether;

        // advance time to a point where the token is tradeable at a reasonable price
        vm.warp(40 days);

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(token1, targetAmount);

        // trade
        vm.expectRevert(ICarbonVortex.InsufficientNativeTokenSent.selector);
        carbonVortex.trade{ value: expectedSourceAmount - 1 }(token1, targetAmount, expectedSourceAmount);
    }

    /// @dev test should revert if source amount exceeds max input on token to target token trades
    function testShouldRevertIfSourceAmountExceedsMaxInputOnTokenToTargetTokenTrades() public {
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token1, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        carbonVortex.execute(tokens);

        // trade target token for token1
        uint128 targetAmount = 1 ether;

        // advance time to a point where the token is tradeable at a reasonable price
        vm.warp(40 days);

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(token1, targetAmount);
        // set max input to less than the expected source amount
        uint128 maxInput = expectedSourceAmount - 1;

        // trade
        vm.expectRevert(ICarbonVortex.GreaterThanMaxInput.selector);
        carbonVortex.trade{ value: expectedSourceAmount }(token1, targetAmount, maxInput);
    }

    /// @dev test should revert if source amount exceeds max input on target token to final target token trades
    function testShouldRevertIfSourceAmountExceedsMaxInputOnTargetTokenToFinalTargetTokenTrades() public {
        vm.prank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        // execute
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // trade target token for final target token
        uint128 targetAmount = 1 ether;

        // advance time to a point where the token is tradeable at a reasonable price
        vm.warp(40 days);

        // get the expected trade input for 1 ether of target token
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(targetToken, targetAmount);
        // set max input to less than the expected source amount
        uint128 maxInput = expectedSourceAmount - 1;

        // trade
        vm.expectRevert(ICarbonVortex.GreaterThanMaxInput.selector);
        carbonVortex.trade(targetToken, targetAmount, maxInput);
    }

    /// @dev test should properly return price for the target token after a big sale
    /// @dev this tests the bucketing flow for target token
    function testShouldProperlyReturnTargetTokenPriceAfterBigSale() public {
        Token token = targetToken;

        // set fees
        uint256 accumulatedFees = 300 ether;
        vm.prank(admin);
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(targetToken);

        // assert initial price is correct
        assertEq(initialPrice.sourceAmount, price.sourceAmount);
        assertEq(initialPrice.targetAmount, price.targetAmount);

        uint256 timeIncrease = 40 days;

        // set timestamp to 40 days
        // need some time to pass so the target token gets to a tradeable price
        vm.warp(timeIncrease + 1);

        ICarbonVortex.Price memory priceBeforeReset = carbonVortex.tokenPrice(token);

        // approve finalTarget token
        finalTargetToken.safeApprove(address(carbonVortex), type(uint256).max);

        ICarbonVortex.Price memory expectedNewPrice = ICarbonVortex.Price({
            sourceAmount: priceBeforeReset.sourceAmount * carbonVortex.priceResetMultiplier(),
            targetAmount: priceBeforeReset.targetAmount
        });

        // check target token halflife is correct before trade
        uint32 targetTokenHalfLife = carbonVortex.targetTokenPriceDecayHalfLife();
        assertEq(targetTokenHalfLife, PRICE_DECAY_HALFLIFE_DEFAULT);

        // trade 95% of the target token sale amount
        uint128 currentTargetTokenSaleAmount = uint128(carbonVortex.targetTokenSaleAmount().initial);
        uint128 tradeAmount = (currentTargetTokenSaleAmount * 95) / 100;
        // get expected input
        uint128 expectedInput = carbonVortex.expectedTradeInput(token, tradeAmount);
        vm.expectEmit();
        emit PriceUpdated(token, expectedNewPrice);
        carbonVortex.trade(token, tradeAmount, expectedInput);

        // price has been reset at this point

        // get price after reset
        ICarbonVortex.Price memory priceAfterReset = carbonVortex.tokenPrice(token);

        // assert price has been reset to price * 2 (price reset multiplier)
        assertEq(priceAfterReset.targetAmount, priceBeforeReset.targetAmount);
        assertEq(priceAfterReset.sourceAmount, priceBeforeReset.sourceAmount * carbonVortex.priceResetMultiplier());

        // now time decay for the price has slowed down

        // check if halflife decay has slowed down - should be 10 days
        targetTokenHalfLife = carbonVortex.targetTokenPriceDecayHalfLife();

        assertEq(targetTokenHalfLife, 10 days);

        // increase timestamp by 10 days (half-life time)
        vm.warp(timeIncrease + 10 days + 1);

        // get new price
        ICarbonVortex.Price memory priceAfterHalfLife = carbonVortex.tokenPrice(token);

        // assert price has decreased by half
        assertEq(priceAfterHalfLife.sourceAmount, priceAfterReset.sourceAmount / 2);
        assertEq(priceAfterHalfLife.targetAmount, priceAfterReset.targetAmount);

        // --- repeat flow to make sure it works correctly ---

        // get expected input
        expectedInput = carbonVortex.expectedTradeInput(token, tradeAmount);
        // trade 95% of the target token sale amount
        carbonVortex.trade(token, tradeAmount, expectedInput);

        // price has been reset at this point

        // get price after reset
        priceAfterReset = carbonVortex.tokenPrice(token);

        // assert price has been reset to price * 2 (price reset multiplier)
        assertEq(priceAfterReset.targetAmount, priceBeforeReset.targetAmount);
        assertEq(priceAfterReset.sourceAmount, priceBeforeReset.sourceAmount * carbonVortex.priceResetMultiplier());

        // increase timestamp by 10 more days (half-life time)
        vm.warp(timeIncrease + 20 days + 1);
        priceAfterHalfLife = carbonVortex.tokenPrice(token);

        // assert price has decreased by half
        assertEq(priceAfterHalfLife.sourceAmount, priceAfterReset.sourceAmount / 2);
        assertEq(priceAfterHalfLife.targetAmount, priceAfterReset.targetAmount);
    }

    /// @dev test auction for the target token gets reset on execute if below the amount available is < min sale amount
    function testShouldResetAuctionForTargetTokenOnExecuteIfBelowTheMinSaleAmount() public {
        Token token = targetToken;

        // set fees
        uint256 accumulatedFees = 100 ether;
        vm.prank(admin);
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(targetToken);

        // assert initial price is correct
        assertEq(initialPrice.sourceAmount, price.sourceAmount);
        assertEq(initialPrice.targetAmount, price.targetAmount);

        uint256 timeIncrease = 40 days;

        // set timestamp to 40 days
        // need some time to pass so the target token gets to a tradeable price
        vm.warp(timeIncrease + 1);

        // approve finalTarget token
        finalTargetToken.safeApprove(address(carbonVortex), type(uint256).max);

        // trade 95% of the target token sale amount
        uint128 currentTargetTokenSaleAmount = uint128(carbonVortex.targetTokenSaleAmount().initial);
        uint128 tradeAmount = (currentTargetTokenSaleAmount * 95) / 100;
        uint128 expectedInput = carbonVortex.expectedTradeInput(token, tradeAmount);
        carbonVortex.trade(token, tradeAmount, expectedInput);

        // increase timestamp by 10 days (half-life time)
        vm.warp(timeIncrease + 10 days + 1);

        // accumulate more fees so that execute can reset the auction
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        // execute
        carbonVortex.execute(tokens);
        // get token price
        ICarbonVortex.Price memory priceAfterReset = carbonVortex.tokenPrice(token);
        // assert price is equal to initial price
        assertEq(priceAfterReset.sourceAmount, initialPrice.sourceAmount);
        assertEq(priceAfterReset.targetAmount, initialPrice.targetAmount);
    }

    /// @dev test should reset the auction for a token after a big sale
    function testShouldResetAuctionForTokenAfterABigSale() public {
        Token token = token1;

        // set fees
        uint256 accumulatedFees = 100 ether;
        vm.prank(admin);
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(token1);

        // assert initial price is correct
        assertEq(initialPrice.sourceAmount, price.sourceAmount);
        assertEq(initialPrice.targetAmount, price.targetAmount);

        uint256 timeIncrease = 40 days;

        // set timestamp to 40 days
        // need some time to pass so the target token gets to a tradeable price
        vm.warp(timeIncrease + 1);

        // approve finalTarget token
        finalTargetToken.safeApprove(address(carbonVortex), type(uint256).max);

        // trade 50% of the token sale amount
        uint128 currentAmountAvailableForTrading = carbonVortex.amountAvailableForTrading(token);
        uint128 minSaleAmount = carbonVortex.minTokenSaleAmount(token);
        uint128 tradeAmount = currentAmountAvailableForTrading + 1 - minSaleAmount;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, tradeAmount);
        vm.expectEmit();
        emit TradingReset(token, initialPrice);
        carbonVortex.trade{ value: sourceAmount }(token, tradeAmount, sourceAmount);

        // price has been reset at this point

        // get price after reset
        price = carbonVortex.tokenPrice(token);

        // assert price has been reset to the initial price (max)
        assertEq(price.sourceAmount, initialPrice.sourceAmount);
        assertEq(price.targetAmount, initialPrice.targetAmount);
    }

    /// @dev test should emit trading reset for token after a big sale
    function testShouldEmitTradingResetForTokenAfterABigSale() public {
        Token token = token1;

        // set fees
        uint256 accumulatedFees = 100 ether;
        vm.prank(admin);
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(token1);

        // assert initial price is correct
        assertEq(initialPrice.sourceAmount, price.sourceAmount);
        assertEq(initialPrice.targetAmount, price.targetAmount);

        uint256 timeIncrease = 40 days;

        // set timestamp to 40 days
        // need some time to pass so the target token gets to a tradeable price
        vm.warp(timeIncrease + 1);

        // approve finalTarget token
        finalTargetToken.safeApprove(address(carbonVortex), type(uint256).max);

        // trade 50% of the available tokens
        uint128 currentAmountAvailableForTrading = carbonVortex.amountAvailableForTrading(token);
        uint128 minSaleAmount = carbonVortex.minTokenSaleAmount(token);
        uint128 tradeAmount = currentAmountAvailableForTrading + 1 - minSaleAmount;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, tradeAmount);
        vm.expectEmit();
        emit TradingReset(token, initialPrice);
        carbonVortex.trade{ value: sourceAmount }(token, tradeAmount, sourceAmount);
    }

    /// @dev test should emit min token sale amount updated for token after a big sale
    function testShouldEmitMinTokenSaleAmountUpdatedForTokenAfterABigSale() public {
        Token token = token1;

        // set fees
        uint256 accumulatedFees = 100 ether;
        vm.prank(admin);
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        ICarbonVortex.Price memory price = ICarbonVortex.Price({
            sourceAmount: INITIAL_PRICE_SOURCE_AMOUNT,
            targetAmount: INITIAL_PRICE_TARGET_AMOUNT
        });

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(token1);

        // assert initial price is correct
        assertEq(initialPrice.sourceAmount, price.sourceAmount);
        assertEq(initialPrice.targetAmount, price.targetAmount);

        uint256 timeIncrease = 40 days;

        // set timestamp to 40 days
        // need some time to pass so the target token gets to a tradeable price
        vm.warp(timeIncrease + 1);

        // approve finalTarget token
        finalTargetToken.safeApprove(address(carbonVortex), type(uint256).max);

        // trade 50% of the available tokens
        uint128 currentAmountAvailableForTrading = carbonVortex.amountAvailableForTrading(token);
        uint128 minSaleAmount = carbonVortex.minTokenSaleAmount(token);
        uint128 tradeAmount = currentAmountAvailableForTrading + 1 - minSaleAmount;
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, tradeAmount);

        uint128 expectedTokenSaleAmount = tradeAmount / 2 - 1;

        vm.expectEmit();
        emit MinTokenSaleAmountUpdated(token, minSaleAmount, expectedTokenSaleAmount);
        carbonVortex.trade{ value: sourceAmount }(token, tradeAmount, sourceAmount);
    }

    function testAttemptToTradeOnATokenForWhichTradingIsNotEnabledWillRevertWithTradingDisabled() public {
        vm.startPrank(admin);
        Token token = token1;

        uint256 accumulatedFees = 100e18;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);
        uint128 tradeAmount = 1;
        // expect revert with pair disabled on attempt to get input / return
        vm.expectRevert(ICarbonVortex.TradingDisabled.selector);
        carbonVortex.trade(token, tradeAmount, 1e18);
    }

    function testAttemptToTradeOnADisabledTokenWillRevertWithPairDisabled() public {
        vm.startPrank(admin);
        Token token = token1;

        uint256 accumulatedFees = 100e18;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to withdraw fees and enable trading
        carbonVortex.execute(tokens);

        vm.stopPrank();
        vm.startPrank(admin);
        uint128 tradeAmount = 1;
        uint128 expectedInput = carbonVortex.expectedTradeInput(token, tradeAmount);
        carbonVortex.disablePair(token, true);
        vm.stopPrank();

        vm.startPrank(user1);
        // expect revert with pair disabled on attempt to get input / return
        vm.expectRevert(ICarbonVortex.PairDisabled.selector);
        carbonVortex.trade(token, tradeAmount, expectedInput);
    }

    function testAttemptToGetInputOrReturnForDisabledTokenWillRevertWithPairDisabled() public {
        vm.startPrank(admin);
        Token token = token1;

        uint256 accumulatedFees = 100e18;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to withdraw fees and enable trading
        carbonVortex.execute(tokens);

        vm.stopPrank();
        vm.prank(admin);
        carbonVortex.disablePair(token, true);

        vm.startPrank(user1);
        // expect revert with pair disabled on attempt to get input / return
        vm.expectRevert(ICarbonVortex.PairDisabled.selector);
        carbonVortex.expectedTradeInput(token, 100);
        vm.expectRevert(ICarbonVortex.PairDisabled.selector);
        carbonVortex.expectedTradeReturn(token, 100);
    }

    function testShouldReturnTotalFeesAvailableForAllVaults() public {
        vm.startPrank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token1, accumulatedFees);
        // transfer fees to vault and old vortex
        token1.safeTransfer(address(carbonVortex), accumulatedFees);
        token1.safeTransfer(address(vault), accumulatedFees);

        vm.startPrank(user1);

        // get total fees
        uint256 totalFees = carbonVortex.availableTokens(token1);

        // assert total fees is correct
        assertEq(totalFees, accumulatedFees * 3);
    }

    /// @dev test that there isn't an incorrect reading of the 0x0 address balance
    function testShouldReturnTotalFeesAvailableCorrectlyIfCarbonControllerIsTheZeroAddress() public {
        // deploy new vortex with carbon controller set to 0x0
        deployCarbonVortex(address(0), vault, oldVortex, transferAddress, targetToken, finalTargetToken);
        vm.startPrank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        // transfer fees to vault and old vortex
        token1.safeTransfer(address(carbonVortex), accumulatedFees);
        token1.safeTransfer(address(vault), accumulatedFees);

        vm.startPrank(user1);

        // get total fees
        uint256 totalFees = carbonVortex.availableTokens(token1);

        // assert total fees is correct
        assertEq(totalFees, accumulatedFees * 2);
    }

    /// @dev test that there isn't an incorrect reading of the 0x0 address balance
    function testShouldReturnTotalFeesAvailableCorrectlyIfTheVaultIsTheZeroAddress() public {
        // deploy new vortex with the vault set to 0x0
        deployCarbonVortex(
            address(carbonController),
            address(0),
            oldVortex,
            transferAddress,
            targetToken,
            finalTargetToken
        );
        vm.startPrank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        // increment fees in the carbon controller
        carbonController.testSetAccumulatedFees(token1, accumulatedFees);
        // transfer fees to vault and old vortex
        token1.safeTransfer(address(oldVortex), accumulatedFees);

        vm.startPrank(user1);

        // get total fees
        uint256 totalFees = carbonVortex.availableTokens(token1);

        // assert total fees is correct
        assertEq(totalFees, accumulatedFees * 2);
    }

    /// @dev test that there isn't an incorrect reading of the 0x0 address balance
    function testShouldReturnTotalFeesAvailableCorrectlyIfTheOldVortexIsTheZeroAddress() public {
        // deploy new vortex with the vault set to 0x0
        deployCarbonVortex(
            address(carbonController),
            address(vault),
            address(0),
            transferAddress,
            targetToken,
            finalTargetToken
        );
        vm.startPrank(admin);
        // set fees
        uint256 accumulatedFees = 100 ether;
        // increment fees in the carbon controller
        carbonController.testSetAccumulatedFees(token1, accumulatedFees);
        // transfer fees to vault and old vortex
        token1.safeTransfer(address(oldVortex), accumulatedFees);
        token1.safeTransfer(address(vault), accumulatedFees);

        vm.startPrank(user1);

        // get total fees
        uint256 totalFees = carbonVortex.availableTokens(token1);

        // assert total fees is correct
        assertEq(totalFees, accumulatedFees * 2);
    }

    /// @dev test should return the correct amount available for trading for the target token
    function testShouldReturnTheAmountAvailableForTradingForTheTargetToken(uint256 accumulatedFees) public {
        vm.prank(admin);

        accumulatedFees = bound(accumulatedFees, 0, MAX_WITHDRAW_AMOUNT);
        carbonController.testSetAccumulatedFees(targetToken, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // calculate user reward
        uint128 expectedReward = uint128((carbonVortex.rewardsPPM() * accumulatedFees) / PPM_RESOLUTION);

        // get the available balance
        uint128 availableBalance = carbonVortex.amountAvailableForTrading(targetToken);

        // get the target token max sale amount
        uint128 targetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().initial;
        // calculate expected available balance
        uint128 expectedAvailableBalance = uint128(Math.min(targetTokenSaleAmount, accumulatedFees - expectedReward));

        // assert available balance is correct
        assertEq(availableBalance, expectedAvailableBalance);
    }

    /// @dev test should return the correct amount available for trading for a token
    function testShouldReturnTheAmountAvailableForTradingForAToken(uint256 accumulatedFees) public {
        vm.prank(admin);

        Token token = token1;

        accumulatedFees = bound(accumulatedFees, 0, MAX_WITHDRAW_AMOUNT);
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // calculate user reward
        uint128 expectedReward = uint128((carbonVortex.rewardsPPM() * accumulatedFees) / PPM_RESOLUTION);

        // get the available balance
        uint128 availableBalance = carbonVortex.amountAvailableForTrading(token);

        // assert available balance is correct
        assertEq(availableBalance, accumulatedFees - expectedReward);
    }

    /// @dev test should return the expected trade input for a token
    function testShouldReturnTheExpectedTradeInputForAToken() public {
        vm.prank(admin);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase time so that the dutch auction price gets to a tradeable level
        vm.warp(40 days);

        // get the expected trade input for 1 ether of token
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, 1 ether);

        uint128 expectedSourceAmount = 281479493033612000000;

        // assert expected trade input is correct
        assertEq(sourceAmount, expectedSourceAmount);
    }

    /// @dev test should return the expected trade return for a token
    function testShouldReturnTheExpectedReturnForAToken() public {
        vm.prank(admin);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase time so that the dutch auction price gets to a tradeable level
        vm.warp(40 days);

        // get the expected trade input for 1 ether of token
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, 1 ether);

        // get the expected trade return for the source amount
        uint128 targetAmount = carbonVortex.expectedTradeReturn(token, sourceAmount);

        // assert expected trade return is correct
        assertEq(targetAmount, 1 ether);
    }

    /// @dev test should return the target token
    function testShouldReturnTheTargetToken() public view {
        assertEq(Token.unwrap(carbonVortex.targetToken()), Token.unwrap(targetToken));
    }

    /// @dev test should return the final target token
    function testShouldReturnTheFinalTargetToken() public view {
        assertEq(Token.unwrap(carbonVortex.finalTargetToken()), Token.unwrap(finalTargetToken));
    }

    /// @dev test should revert on expected trade input if the target amount is larger than the available balance
    function testShouldRevertOnExpectedTradeInputIfTheTargetAmountIsLargerThanTheAvailableBalance() public {
        vm.prank(admin);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get the available balance
        uint128 availableBalance = carbonVortex.amountAvailableForTrading(token);

        // get the expected trade input for a larger amount than the available balance
        vm.expectRevert(ICarbonVortex.InsufficientAmountForTrading.selector);
        carbonVortex.expectedTradeInput(token, availableBalance + 1);
    }

    /// @dev test should revert on expected trade return if the target amount is larger than the available balance
    function testShouldRevertOnExpectedTradeReturnIfTheTargetAmountIsLargerThanTheAvailableBalance() public {
        vm.prank(admin);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to a tradeable level
        vm.warp(40 days);

        // get the available balance
        uint128 availableBalance = carbonVortex.amountAvailableForTrading(token);

        // get the expected max source amount
        uint128 expectedSourceAmount = carbonVortex.expectedTradeInput(token, availableBalance);

        // get the expected trade return for a larger amount than the available balance
        vm.expectRevert(ICarbonVortex.InsufficientAmountForTrading.selector);
        carbonVortex.expectedTradeReturn(token, expectedSourceAmount * 2);
    }

    /// @dev test should revert expected trade return if the auction has reached an invalid price
    function testShouldRevertExpectedTradeReturnIfTheTheAuctionHasReachedAnInvalidPrice() public {
        vm.prank(admin);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to an invalid level
        // after 64 days the price will be sourceAmount: 0, targetAmount: 1e12
        vm.warp(64 days + 1);

        vm.expectRevert(ICarbonVortex.InvalidPrice.selector);
        carbonVortex.expectedTradeReturn(token, 1);
    }

    /// @dev test should revert expected trade input if the auction has reached an invalid price
    function testShouldRevertExpectedTradeInputIfTheTheAuctionHasReachedAnInvalidPrice() public {
        vm.prank(admin);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to an invalid level
        vm.warp(64 days + 1);

        vm.expectRevert(ICarbonVortex.InvalidPrice.selector);
        carbonVortex.expectedTradeInput(token, 1);
    }

    /// @dev test should revert expected trade input for token for which trading is not enabled
    function testShouldRevertExpectedTradeInputForTokenForWhichTradingIsNotEnabled() public {
        vm.startPrank(user1);
        // expect revert with trading disabled on attempt to get input / return
        vm.expectRevert(ICarbonVortex.TradingDisabled.selector);
        carbonVortex.expectedTradeInput(token1, 1);
    }

    /// @dev test should revert expected trade return for token for which trading is not enabled
    function testShouldRevertExpectedTradeReturnForTokenForWhichTradingIsNotEnabled() public {
        vm.startPrank(user1);
        // expect revert with trading disabled on attempt to get input / return
        vm.expectRevert(ICarbonVortex.TradingDisabled.selector);
        carbonVortex.expectedTradeReturn(token1, 1);
    }

    /**
     * @dev --- auction price decay tests ---
     */

    /// @dev test that auction price can be reset if it progresses to the minimum possible
    function testAuctionPriceCanBeResetIfItProgressesToTheMinimum(uint256 idx, uint256 accumulatedFees) public {
        vm.prank(admin);

        idx = bound(idx, 0, 2);

        accumulatedFees = bound(accumulatedFees, 1, 150 ether);

        Token[3] memory tokensToTestWith = [token1, token2, targetToken];
        Token token = tokensToTestWith[idx];

        uint256 accumulatedFeesInitial = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFeesInitial);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to the lowest level
        // (after 64 days we will reach the minimum price)
        vm.warp(64 days + 1);

        // expect price is invalid - 0 source amount
        vm.expectRevert(ICarbonVortex.InvalidPrice.selector);
        // trade
        carbonVortex.trade{ value: 1 }(token, 1, 1e18);

        // assert price source amount is 0
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);
        assertEq(price.sourceAmount, 0);

        // call execute after some more funds have been accumulated
        token.safeTransfer(address(vault), accumulatedFees);

        carbonVortex.execute(tokens);

        // check price has been reset
        price = carbonVortex.tokenPrice(token);
        assertEq(price.sourceAmount, INITIAL_PRICE_SOURCE_AMOUNT);
        assertEq(price.targetAmount, INITIAL_PRICE_TARGET_AMOUNT);
    }

    /// @dev test that auction price for the target token can be reset if it progresses to the minimum possible
    function testAuctionPriceCanBeResetIfItProgressesToTheMinimumForTheTargetToken() public {
        vm.prank(admin);

        Token token = targetToken;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to the lowest level
        // (after 64 days we will reach the minimum price)
        vm.warp(64 days + 1);

        // expect price is invalid on trade - 0 source amount
        vm.expectRevert(ICarbonVortex.InvalidPrice.selector);
        // trade
        carbonVortex.trade{ value: 1 }(token, 1, 1e18);

        // assert price source amount is 0
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);
        assertEq(price.sourceAmount, 0);

        // call execute after some more funds have been accumulated
        token.safeTransfer(address(vault), 200 ether);

        carbonVortex.execute(tokens);

        // check price has been reset
        price = carbonVortex.tokenPrice(token);
        assertEq(price.sourceAmount, INITIAL_PRICE_SOURCE_AMOUNT);
        assertEq(price.targetAmount, INITIAL_PRICE_TARGET_AMOUNT);
    }

    /// @dev test that auction price reverts after more than 64 days but still can be reset
    function testAuctionPriceRevertsAfterMoreThan64Days(uint256 timePassed) public {
        vm.prank(admin);

        timePassed = bound(timePassed, 65 days + 1, 365 days);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to the lowest level
        // (after 65 days the exp price function will revert)
        vm.warp(timePassed);

        // expect price is invalid - arithmetic underflow or overflow (0x11)
        vm.expectRevert();
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);

        // call execute after some more funds have been accumulated
        token.safeTransfer(address(vault), 100 ether);

        carbonVortex.execute(tokens);

        // check price has been reset
        price = carbonVortex.tokenPrice(token);
        assertEq(price.sourceAmount, INITIAL_PRICE_SOURCE_AMOUNT);
        assertEq(price.targetAmount, INITIAL_PRICE_TARGET_AMOUNT);
    }

    /// @dev test that auction doesn't get reset after more than 64 days have passed if no funds have been accumulated
    function testAuctionDoesntGetResetOnExecuteIfNoFundsHaveBeenAccumulatedAfter64Days(uint256 timePassed) public {
        vm.prank(admin);

        timePassed = bound(timePassed, 65 days + 1, 365 days);

        Token token = token1;

        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets to the lowest level
        // (after 65 days the exp price function will revert)
        vm.warp(timePassed);

        // expect price is invalid - arithmetic underflow or overflow (0x11)
        vm.expectRevert();
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);

        carbonVortex.execute(tokens);

        // expect price is still invalid - arithmetic underflow or overflow (0x11)
        vm.expectRevert();
        price = carbonVortex.tokenPrice(token);
    }

    /// @dev test that auction cannot be reset before 64 days have passed (128 halflifes)
    /// @dev test with token1, token2 and targetToken
    /// @dev initial accumulated fees for token are 100 ether, on next execute from 0 to 99 ether are added
    function testAuctionCannotBeResetBefore64Days(uint256 idx, uint256 timePassed, uint256 accumulatedFees) public {
        vm.prank(admin);

        idx = bound(idx, 0, 2);

        timePassed = bound(timePassed, 63 days, 64 days - 1);

        accumulatedFees = bound(accumulatedFees, 0, 99 ether);

        Token[3] memory tokensToTestWith = [token1, token2, targetToken];
        Token token = tokensToTestWith[idx];

        uint256 accumulatedFeesInitial = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFeesInitial);

        vm.startPrank(user1);

        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // increase the dutch auction so that the price gets right before the lowest level
        vm.warp(timePassed);

        // expect price is not invalid - no revert
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);
        // check price is above 0
        assertTrue(price.sourceAmount > 0);

        // call execute after some more funds have been accumulated
        token.safeTransfer(address(vault), accumulatedFees);

        carbonVortex.execute(tokens);

        // check price hasn't been reset
        ICarbonVortex.Price memory newPrice = carbonVortex.tokenPrice(token);
        assertEq(newPrice.sourceAmount, price.sourceAmount);
        assertEq(newPrice.targetAmount, price.targetAmount);
    }

    /// @dev test price behaviour for a token (not the target token) at auction start
    function testAuctionPriceBehaviourForTokenAtStart() public {
        vm.prank(admin);

        Token token = token1;
        // set accumulated fees for token
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(token);
        // check price is equal to start price
        assertEq(initialPrice.sourceAmount, INITIAL_PRICE_SOURCE_AMOUNT);
        assertEq(initialPrice.targetAmount, INITIAL_PRICE_TARGET_AMOUNT);

        // INITIAL_PRICE_TARGET_AMOUNT == 1e12

        // check source amount required for 1e12 targetAmount of token
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, 1e12);
        // expect the source amount to be equal to the uint128.max value
        // this means user needs to send the maximum possible amount of target token to receive 1e12 of token
        assertEq(sourceAmount, type(uint128).max);

        // check that retrieving more than 1e12 of targetAmount reverts since the value is too large
        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        carbonVortex.expectedTradeInput(token, 1e12 + 1);

        // check target amount required for 1 sourceAmount of token
        uint128 targetAmount = carbonVortex.expectedTradeReturn(token, sourceAmount);
        // expect the target amount to be equal to 1e12
        assertEq(targetAmount, 1e12);
    }

    /// @dev test price behaviour for the target token at auction start
    function testAuctionPriceBehaviourForTargetTokenAtStart() public {
        vm.prank(admin);

        Token token = targetToken;
        // set accumulated fees for token
        uint256 accumulatedFees = 100 ether;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to initialize the dutch auction
        carbonVortex.execute(tokens);

        // get price after execute (dutch auction started with the initial price)
        ICarbonVortex.Price memory initialPrice = carbonVortex.tokenPrice(token);
        // check price is equal to start price
        assertEq(initialPrice.sourceAmount, INITIAL_PRICE_SOURCE_AMOUNT);
        assertEq(initialPrice.targetAmount, INITIAL_PRICE_TARGET_AMOUNT);

        // INITIAL_PRICE_TARGET_AMOUNT == 1e12

        // check source amount required for 1e12 targetAmount of token
        uint128 sourceAmount = carbonVortex.expectedTradeInput(token, 1e12);
        // expect the source amount to be equal to the uint128.max value
        // this means user needs to send the maximum possible amount of final target token to receive 1e12 of targetToken
        assertEq(sourceAmount, type(uint128).max);

        // check that retrieving more than 1e12 of targetAmount reverts since the value is too large
        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        carbonVortex.expectedTradeInput(token, 1e12 + 1);

        // check target amount required for 1 sourceAmount of token
        uint128 targetAmount = carbonVortex.expectedTradeReturn(token, sourceAmount);
        // expect the target amount to be equal to 1e12
        assertEq(targetAmount, 1e12);
    }

    /// @dev test correct prices retrieved by tokenPrice as the auction continues for a token
    function testPricesAtTimestampsVortex() public {
        // test the timestamp at every 1 hour
        vm.startPrank(admin);

        // accumulate funds in the vortex
        Token token = token1;
        uint256 accumulatedFees = 100e18;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        // execute so the auction starts
        // generate a token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        carbonVortex.execute(tokens);

        // get test cases from the vortex test case parser
        VortexTestCaseParser.TestCase memory testCase = testCaseParser.getTestCase();

        // decay the price for 1 hour until it reaches 64 days and check it against the test case data
        for (uint256 i = 1; i < 64 * 24; i++) {
            uint256 timestamp = i * 1 hours;
            // set timestamp
            vm.warp(timestamp);
            // get token price at this timestamp
            ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);
            // get test data for this timestamp
            VortexTestCaseParser.PriceAtTimestamp memory priceAtTimestamp = testCase.pricesAtTimestamp[i];
            // assert test data matches the actual token price data
            assertEq(priceAtTimestamp.timestamp, timestamp);
            assertEq(priceAtTimestamp.sourceAmount, price.sourceAmount);
            assertEq(priceAtTimestamp.targetAmount, price.targetAmount);
        }
    }

    /**
     * @dev --- admin-controlled function tests ---
     */

    /**
     * @dev rewards ppm tests
     */

    /// @dev test that setRewardsPPM should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheRewardsPPM() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setRewardsPPM(REWARDS_PPM_UPDATED);
    }

    /// @dev test that setRewardsPPM should revert when setting to an invalid fee
    function testShouldRevertSettingTheRewardsPPMWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(InvalidFee.selector);
        carbonVortex.setRewardsPPM(PPM_RESOLUTION + 1);
    }

    /// @dev test that setRewardsPPM with the same rewards ppm should be ignored
    function testShouldIgnoreSettingTheRewardsPPMWithTheSameValue() public {
        // get rewards ppm before
        uint256 rewardsPPM = carbonVortex.rewardsPPM();
        vm.prank(admin);
        carbonVortex.setRewardsPPM(REWARDS_PPM_DEFAULT);
        // get rewards ppm after
        uint256 rewardsPPMAfter = carbonVortex.rewardsPPM();
        // assert that the rewards ppm has not changed
        assertEq(rewardsPPM, rewardsPPMAfter);
    }

    /// @dev test that setRewardsPPM with the same rewards ppm should be ignored
    function testFailShouldIgnoreSettingTheSameRewardsPPM() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit RewardsUpdated(REWARDS_PPM_DEFAULT, REWARDS_PPM_DEFAULT);
        carbonVortex.setRewardsPPM(REWARDS_PPM_DEFAULT);
    }

    /// @dev test that admin should be able to update the rewards ppm
    function testShouldBeAbleToSetAndUpdateTheRewardsPPM() public {
        vm.startPrank(admin);
        uint256 rewardsPPM = carbonVortex.rewardsPPM();
        assertEq(rewardsPPM, REWARDS_PPM_DEFAULT);

        vm.expectEmit();
        emit RewardsUpdated(REWARDS_PPM_DEFAULT, REWARDS_PPM_UPDATED);
        carbonVortex.setRewardsPPM(REWARDS_PPM_UPDATED);

        rewardsPPM = carbonVortex.rewardsPPM();
        assertEq(rewardsPPM, REWARDS_PPM_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev price reset multiplier tests
     */

    /// @dev test that setPriceResetMultiplier should revert when a non-admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetThePriceResetMultiplier() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setPriceResetMultiplier(PRICE_RESET_MULTIPLIER_UPDATED);
    }

    /// @dev test that setPriceResetMultiplier should revert when setting to an invalid value
    function testShouldRevertSettingThePriceResetMultiplierWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setPriceResetMultiplier(0);
    }

    /// @dev test that setPriceResetMultiplier with the same value should be ignored
    function testShouldIgnoreSettingTheSamePriceResetMultiplier() public {
        // get price reset multiplier before
        uint32 priceResetMultiplier = carbonVortex.priceResetMultiplier();
        vm.prank(admin);
        carbonVortex.setPriceResetMultiplier(PRICE_RESET_MULTIPLIER_DEFAULT);
        // get price reset multiplier after
        uint32 priceResetMultiplierAfter = carbonVortex.priceResetMultiplier();
        // assert that the price reset multiplier has not changed
        assertEq(priceResetMultiplier, priceResetMultiplierAfter);
    }

    /// @dev test that setPriceResetMultiplier with the same value should be ignored
    function testFailShouldIgnoreSettingTheSamePriceResetMultiplier() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit PriceResetMultiplierUpdated(PRICE_RESET_MULTIPLIER_DEFAULT, PRICE_RESET_MULTIPLIER_DEFAULT);
        carbonVortex.setPriceResetMultiplier(PRICE_RESET_MULTIPLIER_DEFAULT);
    }

    /// @dev test that admin should be able to update the price reset multiplier
    function testShouldBeAbleToSetAndUpdateThePriceResetMultiplier() public {
        vm.startPrank(admin);
        uint32 priceResetMultiplier = carbonVortex.priceResetMultiplier();
        assertEq(priceResetMultiplier, PRICE_RESET_MULTIPLIER_DEFAULT);

        vm.expectEmit(true, true, true, true);
        emit PriceResetMultiplierUpdated(PRICE_RESET_MULTIPLIER_DEFAULT, PRICE_RESET_MULTIPLIER_UPDATED);
        carbonVortex.setPriceResetMultiplier(PRICE_RESET_MULTIPLIER_UPDATED);

        priceResetMultiplier = carbonVortex.priceResetMultiplier();
        assertEq(priceResetMultiplier, PRICE_RESET_MULTIPLIER_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev min token sale amount multiplier tests
     */

    /// @dev test that setMinTokenSaleAmountMultiplier should revert when a non-admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheMinTokenSaleAmountMultiplier() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setMinTokenSaleAmountMultiplier(MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_UPDATED);
    }

    /// @dev test that setMinTokenSaleAmountMultiplier should revert when setting to an invalid value
    function testShouldRevertSettingTheMinTokenSaleAmountMultiplierWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setMinTokenSaleAmountMultiplier(0);
    }

    /// @dev test that setMinTokenSaleAmountMultiplier with the same value should be ignored
    function testShouldIgnoreSettingTheSameMinTokenSaleAmountMultiplier() public {
        // get min token sale amount multiplier before
        uint32 minTokenSaleAmountMultiplier = carbonVortex.minTokenSaleAmountMultiplier();
        vm.prank(admin);
        carbonVortex.setMinTokenSaleAmountMultiplier(MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT);
        // get min token sale amount multiplier after
        uint32 minTokenSaleAmountMultiplierAfter = carbonVortex.minTokenSaleAmountMultiplier();
        // assert that the min token sale amount multiplier has not changed
        assertEq(minTokenSaleAmountMultiplier, minTokenSaleAmountMultiplierAfter);
    }

    /// @dev test that setMinTokenSaleAmountMultiplier with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameMinTokenSaleAmountMultiplier() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit MinTokenSaleAmountMultiplierUpdated(
            MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT,
            MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT
        );
        carbonVortex.setMinTokenSaleAmountMultiplier(MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT);
    }

    /// @dev test that admin should be able to update the minimum token sale amount multiplier
    function testShouldBeAbleToSetAndUpdateTheMinTokenSaleAmountMultiplier() public {
        vm.startPrank(admin);
        uint32 minTokenSaleAmountMultiplier = carbonVortex.minTokenSaleAmountMultiplier();
        assertEq(minTokenSaleAmountMultiplier, MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT);

        vm.expectEmit();
        emit MinTokenSaleAmountMultiplierUpdated(
            MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_DEFAULT,
            MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_UPDATED
        );
        carbonVortex.setMinTokenSaleAmountMultiplier(MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_UPDATED);

        minTokenSaleAmountMultiplier = carbonVortex.minTokenSaleAmountMultiplier();
        assertEq(minTokenSaleAmountMultiplier, MIN_TOKEN_SALE_AMOUNT_MULTIPLIER_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev price decay half-life tests
     */

    /// @dev test that setPriceDecayHalfLife should revert when a non admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetThePriceDecayHalfLife() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_UPDATED);
    }

    /// @dev test that setPriceDecayHalfLife should revert when a setting to an invalid value
    function testShouldRevertSettingThePriceDecayHalfLifeWithAnInvalidFee() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setPriceDecayHalfLife(0);
    }

    /// @dev test that setPriceDecayHalfLife with the same value should be ignored
    function testShouldIgnoreSettingTheSamePriceDecayHalfLife() public {
        // get price decay half-life before
        uint32 priceDecayHalfLife = carbonVortex.priceDecayHalfLife();
        vm.prank(admin);
        carbonVortex.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_DEFAULT);
        // get price decay half-life after
        uint32 priceDecayHalfLifeAfter = carbonVortex.priceDecayHalfLife();
        // assert that the price decay half-life has not changed
        assertEq(priceDecayHalfLife, priceDecayHalfLifeAfter);
    }

    /// @dev test that setPriceDecayHalfLife with the same value should be ignored
    function testFailShouldIgnoreSettingTheSamePriceDecayHalfLife() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit PriceDecayHalfLifeUpdated(PRICE_DECAY_HALFLIFE_DEFAULT, PRICE_DECAY_HALFLIFE_DEFAULT);
        carbonVortex.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_DEFAULT);
    }

    /// @dev test that admin should be able to update the price decay half-life
    function testShouldBeAbleToSetAndUpdateThePriceDecayHalfLife() public {
        vm.startPrank(admin);
        uint32 priceDecayHalfLife = carbonVortex.priceDecayHalfLife();
        assertEq(priceDecayHalfLife, PRICE_DECAY_HALFLIFE_DEFAULT);

        vm.expectEmit();
        emit PriceDecayHalfLifeUpdated(PRICE_DECAY_HALFLIFE_DEFAULT, PRICE_DECAY_HALFLIFE_UPDATED);
        carbonVortex.setPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_UPDATED);

        priceDecayHalfLife = carbonVortex.priceDecayHalfLife();
        assertEq(priceDecayHalfLife, PRICE_DECAY_HALFLIFE_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev target token price decay half-life tests
     */

    /// @dev test that setTargetTokenPriceDecayHalfLife should revert when a non-admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheTargetTokenPriceDecayHalfLife() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setTargetTokenPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_UPDATED);
    }

    /// @dev test that setTargetTokenPriceDecayHalfLife should revert when setting to an invalid value
    function testShouldRevertSettingTheTargetTokenPriceDecayHalfLifeWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setTargetTokenPriceDecayHalfLife(0);
    }

    function testShouldIgnoreSettingTheSameTargetTokenPriceDecayHalfLife() public {
        // get target token price decay half-life before
        uint32 targetTokenPriceDecayHalfLife = carbonVortex.targetTokenPriceDecayHalfLife();
        vm.prank(admin);
        carbonVortex.setTargetTokenPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_DEFAULT);
        // get target token price decay half-life after
        uint32 targetTokenPriceDecayHalfLifeAfter = carbonVortex.targetTokenPriceDecayHalfLife();
        // assert that the target token price decay half-life has not changed
        assertEq(targetTokenPriceDecayHalfLife, targetTokenPriceDecayHalfLifeAfter);
    }

    /// @dev test that setTargetTokenPriceDecayHalfLife with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameTargetTokenPriceDecayHalfLife() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit TargetTokenPriceDecayHalfLifeUpdated(PRICE_DECAY_HALFLIFE_DEFAULT, PRICE_DECAY_HALFLIFE_DEFAULT);
        carbonVortex.setTargetTokenPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_DEFAULT);
    }

    /// @dev test that admin should be able to update the target token price decay half-life
    function testShouldBeAbleToSetAndUpdateTheTargetTokenPriceDecayHalfLife() public {
        vm.startPrank(admin);
        uint32 targetTokenPriceDecayHalfLife = carbonVortex.targetTokenPriceDecayHalfLife();
        assertEq(targetTokenPriceDecayHalfLife, PRICE_DECAY_HALFLIFE_DEFAULT);

        vm.expectEmit();
        emit TargetTokenPriceDecayHalfLifeUpdated(PRICE_DECAY_HALFLIFE_DEFAULT, PRICE_DECAY_HALFLIFE_UPDATED);
        carbonVortex.setTargetTokenPriceDecayHalfLife(PRICE_DECAY_HALFLIFE_UPDATED);

        targetTokenPriceDecayHalfLife = carbonVortex.targetTokenPriceDecayHalfLife();
        assertEq(targetTokenPriceDecayHalfLife, PRICE_DECAY_HALFLIFE_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev target token price decay half-life on reset tests
     */

    /// @dev test that setTargetTokenPriceDecayHalfLifeOnReset should revert when a non-admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheTargetTokenPriceDecayHalfLifeOnReset() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setTargetTokenPriceDecayHalfLifeOnReset(TARGET_TOKEN_PRICE_DECAY_HALFLIFE_UPDATED);
    }

    /// @dev test that setTargetTokenPriceDecayHalfLifeOnReset should revert when setting to an invalid value
    function testShouldRevertSettingTheTargetTokenPriceDecayHalfLifeOnResetWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setTargetTokenPriceDecayHalfLifeOnReset(0);
    }

    function testShouldIgnoreSettingTheSameTargetTokenPriceDecayHalfLifeOnReset() public {
        uint32 targetTokenPriceDecayHalfLife = carbonVortex.targetTokenPriceDecayHalfLifeOnReset();
        vm.prank(admin);
        carbonVortex.setTargetTokenPriceDecayHalfLifeOnReset(TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT);
        uint32 targetTokenPriceDecayHalfLifeAfter = carbonVortex.targetTokenPriceDecayHalfLifeOnReset();
        assertEq(targetTokenPriceDecayHalfLife, targetTokenPriceDecayHalfLifeAfter);
    }

    /// @dev test that setTargetTokenPriceDecayHalfLifeOnReset with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameTargetTokenPriceDecayHalfLifeOnReset() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit TargetTokenPriceDecayHalfLifeUpdated(
            TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT,
            TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT
        );
        carbonVortex.setTargetTokenPriceDecayHalfLifeOnReset(TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT);
    }

    /// @dev test that admin should be able to update the target token price decay half-life on reset
    function testShouldBeAbleToSetAndUpdateTheTargetTokenPriceDecayHalfLifeOnReset() public {
        vm.startPrank(admin);
        uint32 targetTokenPriceDecayHalfLife = carbonVortex.targetTokenPriceDecayHalfLifeOnReset();
        assertEq(targetTokenPriceDecayHalfLife, TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT);

        vm.expectEmit();
        emit TargetTokenPriceDecayHalfLifeOnResetUpdated(
            TARGET_TOKEN_PRICE_DECAY_HALFLIFE_DEFAULT,
            TARGET_TOKEN_PRICE_DECAY_HALFLIFE_UPDATED
        );
        carbonVortex.setTargetTokenPriceDecayHalfLifeOnReset(TARGET_TOKEN_PRICE_DECAY_HALFLIFE_UPDATED);

        targetTokenPriceDecayHalfLife = carbonVortex.targetTokenPriceDecayHalfLifeOnReset();
        assertEq(targetTokenPriceDecayHalfLife, TARGET_TOKEN_PRICE_DECAY_HALFLIFE_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev min target token sale amount tests
     */

    /// @dev test that setMinTargetTokenSaleAmount should revert when a non-admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheMinTargetTokenSaleAmount() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setMinTargetTokenSaleAmount(MIN_TARGET_TOKEN_SALE_AMOUNT_UPDATED);
    }

    /// @dev test that setMinTargetTokenSaleAmount should revert when setting to an invalid value
    function testShouldRevertSettingTheMinTargetTokenSaleAmountWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setMinTargetTokenSaleAmount(0);
    }

    /// @dev test that setMinTargetTokenSaleAmount with the same value should be ignored
    function testShouldIgnoreSettingTheSameMinTargetTokenSaleAmount() public {
        // get min target token amount before
        uint128 minTargetTokenSaleAmount = carbonVortex.minTargetTokenSaleAmount();
        vm.prank(admin);
        carbonVortex.setMinTargetTokenSaleAmount(MIN_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);
        // get min target token amount after
        uint128 minTargetTokenSaleAmountAfter = carbonVortex.minTargetTokenSaleAmount();
        // assert that the min target token amount has not changed
        assertEq(minTargetTokenSaleAmount, minTargetTokenSaleAmountAfter);
    }

    /// @dev test that setMinTargetTokenSaleAmount with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameMinTargetTokenSaleAmount() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit MinTokenSaleAmountUpdated(
            targetToken,
            MIN_TARGET_TOKEN_SALE_AMOUNT_DEFAULT,
            MIN_TARGET_TOKEN_SALE_AMOUNT_UPDATED
        );
        carbonVortex.setMinTargetTokenSaleAmount(MIN_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);
    }

    /// @dev test that admin should be able to update the min target token sale amount
    function testShouldBeAbleToSetAndUpdateTheMinTargetTokenSaleAmount() public {
        vm.startPrank(admin);
        uint128 minTargetTokenSaleAmount = carbonVortex.minTargetTokenSaleAmount();
        assertEq(minTargetTokenSaleAmount, MIN_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);

        vm.expectEmit();
        emit MinTokenSaleAmountUpdated(
            targetToken,
            MIN_TARGET_TOKEN_SALE_AMOUNT_DEFAULT,
            MIN_TARGET_TOKEN_SALE_AMOUNT_UPDATED
        );
        carbonVortex.setMinTargetTokenSaleAmount(MIN_TARGET_TOKEN_SALE_AMOUNT_UPDATED);

        minTargetTokenSaleAmount = carbonVortex.minTargetTokenSaleAmount();
        assertEq(minTargetTokenSaleAmount, MIN_TARGET_TOKEN_SALE_AMOUNT_UPDATED);
        vm.stopPrank();
    }

    /**
     * @dev max target token sale amount tests
     */

    /// @dev test that setMaxTargetTokenSaleAmount should revert when a non-admin calls it
    function testShouldRevertWhenNonAdminAttemptsToSetTheMaxTargetTokenSaleAmount() public {
        vm.prank(user1);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.setMaxTargetTokenSaleAmount(MAX_TARGET_TOKEN_SALE_AMOUNT_UPDATED);
    }

    /// @dev test that setMaxTargetTokenSaleAmount should revert when setting to an invalid value
    function testShouldRevertSettingTheMaxTargetTokenSaleAmountWithAnInvalidValue() public {
        vm.prank(admin);
        vm.expectRevert(ZeroValue.selector);
        carbonVortex.setMaxTargetTokenSaleAmount(0);
    }

    /// @dev test that setMaxTargetTokenSaleAmount with the same value should be ignored
    function testShouldIgnoreSettingTheSameMaxTargetTokenSaleAmount() public {
        // get max target token amount before
        uint128 maxTargetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().initial;
        vm.prank(admin);
        carbonVortex.setMaxTargetTokenSaleAmount(MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);
        // get max target token amount after
        uint128 maxTargetTokenSaleAmountAfter = carbonVortex.targetTokenSaleAmount().initial;
        // assert that the max target token amount has not changed
        assertEq(maxTargetTokenSaleAmount, maxTargetTokenSaleAmountAfter);
    }

    /// @dev test that setMaxTargetTokenSaleAmount with the same value should be ignored
    function testFailShouldIgnoreSettingTheSameMaxTargetTokenSaleAmount() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit MaxTargetTokenSaleAmountUpdated(
            MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT,
            MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT
        );
        carbonVortex.setMaxTargetTokenSaleAmount(MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);
    }

    /// @dev test that admin should be able to update the max target token sale amount
    function testShouldBeAbleToSetAndUpdateTheMaxTargetTokenSaleAmount() public {
        vm.startPrank(admin);
        uint128 maxTargetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().initial;
        assertEq(maxTargetTokenSaleAmount, MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);

        vm.expectEmit();
        emit MaxTargetTokenSaleAmountUpdated(
            MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT,
            MAX_TARGET_TOKEN_SALE_AMOUNT_UPDATED
        );
        carbonVortex.setMaxTargetTokenSaleAmount(MAX_TARGET_TOKEN_SALE_AMOUNT_UPDATED);

        maxTargetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().initial;
        assertEq(maxTargetTokenSaleAmount, MAX_TARGET_TOKEN_SALE_AMOUNT_UPDATED);
        vm.stopPrank();
    }

    /// @dev test that setting the max target token sale amount to an amount below the current target token sale amount reset the current amount
    function testCurrentTargetTokenSaleAmountIsUpdatedWhenAboveTheNewMaxTargetTokenSaleAmount() public {
        vm.startPrank(admin);
        uint128 targetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().initial;
        assertEq(targetTokenSaleAmount, MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT);

        // set token fees in the carbon controller
        carbonController.testSetAccumulatedFees(targetToken, targetTokenSaleAmount * 2);

        // call execute to set the current target token sale amount
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        carbonVortex.execute(tokens);

        // assert current and max amounts are equal
        uint128 currentTargetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().current;
        assertEq(currentTargetTokenSaleAmount, targetTokenSaleAmount);

        // set the new amount to amount / 2
        uint128 newSaleAmount = MAX_TARGET_TOKEN_SALE_AMOUNT_DEFAULT / 2;
        carbonVortex.setMaxTargetTokenSaleAmount(newSaleAmount);

        // assert both amounts are updated
        targetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().initial;
        currentTargetTokenSaleAmount = carbonVortex.targetTokenSaleAmount().current;
        assertEq(targetTokenSaleAmount, currentTargetTokenSaleAmount);
        vm.stopPrank();
    }

    /**
     * @dev withdrawFunds tests
     */

    /// @dev test should revert when attempting to withdraw funds without the admin role
    function testShouldRevertWhenAttemptingToWithdrawFundsWithoutTheAdminRole() public {
        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 1000;
        vm.prank(user2);
        vm.expectRevert(AccessDenied.selector);
        carbonVortex.withdrawFunds(tokens, user2, withdrawAmounts);
    }

    /// @dev test should revert when attempting to withdraw funds to an invalid address
    function testShouldRevertWhenAttemptingToWithdrawFundsToAnInvalidAddress() public {
        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 1000;
        vm.prank(admin);
        vm.expectRevert(InvalidAddress.selector);
        carbonVortex.withdrawFunds(tokens, payable(address(0)), withdrawAmounts);
    }

    /// @dev test admin should be able to withdraw tokens
    function testAdminShouldBeAbleToWithdrawTokens(uint256 withdrawAmount) public {
        // test withdrawing different amounts of three tokens
        Token[] memory tokens = new Token[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;
        uint256[] memory withdrawAmounts = new uint256[](3);
        withdrawAmounts[0] = bound(withdrawAmount, 0, MAX_WITHDRAW_AMOUNT);
        withdrawAmounts[1] = bound(withdrawAmount, 0, MAX_WITHDRAW_AMOUNT);
        withdrawAmounts[2] = bound(withdrawAmount, 0, MAX_WITHDRAW_AMOUNT);

        vm.startPrank(admin);
        // transfer funds to vortex
        for (uint256 i = 0; i < 3; ++i) {
            tokens[i].safeTransfer(address(carbonVortex), MAX_WITHDRAW_AMOUNT);
        }

        uint256[] memory balancesBeforeVault = new uint256[](3);
        uint256[] memory balancesBeforeUser2 = new uint256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            balancesBeforeVault[i] = tokens[i].balanceOf(address(carbonVortex));
            balancesBeforeUser2[i] = tokens[i].balanceOf(user2);
        }

        // withdraw tokens to user2
        carbonVortex.withdrawFunds(tokens, user2, withdrawAmounts);

        uint256[] memory balancesAfterVault = new uint256[](3);
        uint256[] memory balancesAfterUser2 = new uint256[](3);

        // assert balance differences are correct for each token
        for (uint256 i = 0; i < 3; ++i) {
            balancesAfterVault[i] = tokens[i].balanceOf(address(carbonVortex));
            balancesAfterUser2[i] = tokens[i].balanceOf(user2);
            uint256 balanceWithdrawn = balancesBeforeVault[i] - balancesAfterVault[i];
            uint256 balanceGainUser2 = balancesAfterUser2[i] - balancesBeforeUser2[i];
            assertEq(balanceWithdrawn, withdrawAmounts[i]);
            assertEq(balanceGainUser2, withdrawAmounts[i]);
        }
    }

    /// @dev test admin should be able to withdraw the target token
    function testAdminShouldBeAbleToWithdrawTargetToken(uint256 withdrawAmount) public {
        Token[] memory tokens = new Token[](1);
        tokens[0] = targetToken;
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = bound(withdrawAmount, 0, MAX_WITHDRAW_AMOUNT);

        // transfer eth to the vortex
        vm.deal(address(carbonVortex), MAX_WITHDRAW_AMOUNT);

        uint256 balanceBeforeVault = address(carbonVortex).balance;
        uint256 balanceBeforeUser2 = user2.balance;

        vm.prank(admin);
        // withdraw target token to user2
        carbonVortex.withdrawFunds(tokens, user2, withdrawAmounts);

        uint256 balanceAfterVault = address(carbonVortex).balance;
        uint256 balanceAfterUser2 = user2.balance;

        uint256 balanceWithdrawn = balanceBeforeVault - balanceAfterVault;
        uint256 balanceGainUser2 = balanceAfterUser2 - balanceBeforeUser2;

        assertEq(balanceWithdrawn, withdrawAmounts[0]);
        assertEq(balanceGainUser2, withdrawAmounts[0]);
    }

    /// @dev test withdrawing funds should emit event
    function testWithdrawingFundsShouldEmitEvent() public {
        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 1000;

        vm.startPrank(admin);
        // transfer funds to vortex
        token1.safeTransfer(address(carbonVortex), withdrawAmounts[0]);

        vm.expectEmit();
        emit FundsWithdrawn(tokens, admin, user2, withdrawAmounts);
        // withdraw token to user2
        carbonVortex.withdrawFunds(tokens, user2, withdrawAmounts);

        vm.stopPrank();
    }

    /// @dev test withdrawing funds with mismatch in amount and token length should revert
    function testShouldRevertOnAttemptToWithdrawFundsWithAmountAndTokenLengthMismatch() public {
        Token[] memory tokens = new Token[](1);
        tokens[0] = token1;
        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 1000;
        withdrawAmounts[1] = 1000;

        vm.startPrank(admin);
        // transfer funds to vortex
        token1.safeTransfer(address(carbonVortex), withdrawAmounts[0]);

        // withdraw token to user2
        vm.expectRevert(ICarbonVortex.InvalidAmountLength.selector);
        carbonVortex.withdrawFunds(tokens, user2, withdrawAmounts);

        vm.stopPrank();
    }

    /// @dev test withdrawing funds with zero token length should revert
    function testShouldRevertOnWithdrawFundsWithZeroTokenLength() public {
        Token[] memory tokens = new Token[](0);
        uint256[] memory withdrawAmounts = new uint256[](0);

        vm.startPrank(admin);

        // withdraw token to user2
        vm.expectRevert(ICarbonVortex.InvalidTokenLength.selector);
        carbonVortex.withdrawFunds(tokens, user2, withdrawAmounts);

        vm.stopPrank();
    }

    /**
     * @dev admin pair disable test
     */

    function testAdminShouldBeAbleToDisableTokenPairs() public {
        vm.startPrank(admin);
        Token token = token1;
        vm.expectEmit();
        emit PairDisabledStatusUpdated(token, false, true);
        carbonVortex.disablePair(token, true);

        bool pairDisabled = carbonVortex.pairDisabled(token);
        assertTrue(pairDisabled);

        uint256 accumulatedFees = 100e18;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);
        // check execute doesn't do anything for the token

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        carbonVortex.execute(tokens);

        vm.expectRevert(ICarbonVortex.TradingDisabled.selector);
        carbonVortex.tokenPrice(token);
    }

    function testAdminShouldBeAbleToEnableTokenPairs() public {
        vm.startPrank(admin);
        Token token = token1;
        carbonVortex.disablePair(token, true);

        uint256 accumulatedFees = 100e18;
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        vm.startPrank(user1);

        // create token array
        Token[] memory tokens = new Token[](1);
        tokens[0] = token;
        // execute to withdraw fees
        carbonVortex.execute(tokens);

        // expect to get trading disabled for the token
        vm.expectRevert(ICarbonVortex.TradingDisabled.selector);
        carbonVortex.tokenPrice(token);

        vm.stopPrank();

        // re-enable pair
        vm.startPrank(admin);
        vm.expectEmit();
        emit PairDisabledStatusUpdated(token, true, false);
        carbonVortex.disablePair(token, false);

        bool pairDisabled = carbonVortex.pairDisabled(token);
        assertFalse(pairDisabled);

        // set fees again to withdraw again on execute
        carbonController.testSetAccumulatedFees(token, accumulatedFees);

        // check if token has price after execute
        vm.startPrank(user1);

        carbonVortex.execute(tokens);

        // get price
        ICarbonVortex.Price memory price = carbonVortex.tokenPrice(token);
        // assert price is not 0
        assertNotEq(price.sourceAmount, 0);
        assertNotEq(price.targetAmount, 0);
    }

    /**
     * @dev reentrancy tests
     */

    /// @dev test should revert if reentrancy is attempted on execute
    function testShouldRevertIfReentrancyIsAttemptedOnExecute() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        // set the accumulated fees
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], tokenAmounts[i]);
        }

        // deploy carbonVortex reentrancy contract
        TestReenterCarbonVortex testReentrancy = new TestReenterCarbonVortex(carbonVortex);
        // expect execute to revert
        // reverts in "sendValue" in _allocateRewards in carbonVortex
        vm.expectRevert("Address: unable to send value, recipient may have reverted");
        testReentrancy.tryReenterCarbonVortexExecute(tokens);
        vm.stopPrank();
    }

    /// @dev test should revert if reentrancy is attempted on trade
    function testShouldRevertIfReentrancyIsAttemptedOnTrade() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        // set the accumulated fees
        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], tokenAmounts[i]);
        }

        // execute so that trade can be called
        carbonVortex.execute(tokens);

        // increase time to decay price a bit for the trade
        vm.warp(40 days);

        // deploy carbonVortex reentrancy contract
        TestReenterCarbonVortex testReentrancy = new TestReenterCarbonVortex(carbonVortex);
        // expect execute to revert
        // reverts in "sendValue" in _allocateRewards in carbonVortex
        vm.expectRevert("Address: unable to send value, recipient may have reverted");
        testReentrancy.tryReenterCarbonVortexTrade{ value: 1e18 }(tokens[0], 1, 1e18);
        vm.stopPrank();
    }
}
