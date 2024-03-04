// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";

import { Pair, Pairs } from "../../contracts/carbon/Pairs.sol";

import { InvalidAddress } from "../../contracts/utility/Utils.sol";

import { TestPairs } from "../../contracts/helpers/TestPairs.sol";
import { CarbonController } from "../../contracts/carbon/CarbonController.sol";

import { Token } from "../../contracts/token/Token.sol";

contract PairsTest is TestFixture {
    using Address for address payable;

    // Events

    /**
     * @dev triggered when a new pair is created
     */
    event PairCreated(uint128 indexed pairId, Token indexed token0, Token indexed token1);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
    }

    /**
     * @dev pair creation tests
     */

    /// @dev test that pair creation reverts for non valid addresses
    function testRevertsForNonValidAddresses(uint256 i0, uint256 i1) public {
        vm.startPrank(admin);
        // use two of the below 3 tokens for the strategy
        Token[3] memory tokens = [token0, Token.wrap(address(0)), Token.wrap(address(0))];
        // pick two random numbers from 0 to 2 for the tokens
        i0 = bound(i0, 0, 2);
        i1 = bound(i1, 0, 2);
        vm.assume(i0 != i1);

        vm.expectRevert(InvalidAddress.selector);
        carbonController.createPair(tokens[i0], tokens[i1]);
        vm.stopPrank();
    }

    /// @dev test that pair creation reverts for identical token addresses
    function testShouldRevertWhenAddressesAreIdentical() public {
        vm.startPrank(admin);

        vm.expectRevert(CarbonController.IdenticalAddresses.selector);
        carbonController.createPair(token0, token0);
        vm.stopPrank();
    }

    /// @dev test that pair creation reverts when pair already exists
    function testShouldRevertWhenPairAlreadyExists() public {
        vm.startPrank(admin);

        carbonController.createPair(token0, token1);
        vm.expectRevert(Pairs.PairAlreadyExists.selector);
        carbonController.createPair(token0, token1);
        vm.stopPrank();
    }

    /// @dev test that pair creation emits event and creates a pair
    function testShouldCreateAPair() public {
        vm.startPrank(admin);

        (Token token0Sorted, Token token1Sorted) = sortTokens(token0, token1);

        vm.expectEmit();
        emit PairCreated(1, token0Sorted, token1Sorted);
        carbonController.createPair(token0, token1);

        Token[2][] memory tokens = carbonController.pairs();
        assertEq(Token.unwrap(tokens[0][0]), Token.unwrap(token0Sorted));
        assertEq(Token.unwrap(tokens[0][1]), Token.unwrap(token1Sorted));

        vm.stopPrank();
    }

    /// @dev test that pair creation increases pairId
    function testShouldIncreasePairId() public {
        vm.startPrank(admin);

        // create first pair
        carbonController.createPair(token0, token1);

        (Token token0Sorted, Token token2Sorted) = sortTokens(token0, token2);

        vm.expectEmit();
        emit PairCreated(2, token0Sorted, token2Sorted);
        // create second pair
        carbonController.createPair(token0, token2);

        vm.stopPrank();
    }

    /// @dev test that pair creation sorts tokens properly
    function testSortsTheTokensByAddressValueSizeInAscendingOrder() public {
        vm.startPrank(admin);

        (Token token0Sorted, Token token1Sorted) = sortTokens(token0, token1);

        vm.expectEmit();
        emit PairCreated(1, token0Sorted, token1Sorted);
        carbonController.createPair(token0, token1);

        vm.stopPrank();
    }

    /**
     * @dev pair retrieval tests
     */

    /// @dev test can retrieve pair by providing sorted tokens
    function testShouldRetrievePairMatchingTheProvidedTokens() public {
        vm.startPrank(admin);

        (Token token0Sorted, Token token1Sorted) = sortTokens(token0, token1);
        carbonController.createPair(token0, token1);

        Pair memory pair = carbonController.pair(token0Sorted, token1Sorted);
        assertEq(pair.id, 1);
        assertEq(Token.unwrap(pair.tokens[0]), Token.unwrap(token0Sorted));
        assertEq(Token.unwrap(pair.tokens[1]), Token.unwrap(token1Sorted));

        vm.stopPrank();
    }

    /// @dev test can retrieve pair by providing unsorted tokens
    function testShouldRetrievePairMatchingTheProvidedUnsortedTokens() public {
        vm.startPrank(admin);

        (Token token0Sorted, Token token1Sorted) = sortTokens(token0, token1);
        carbonController.createPair(token0, token1);

        Pair memory pair = carbonController.pair(token1Sorted, token0Sorted);
        assertEq(pair.id, 1);
        assertEq(Token.unwrap(pair.tokens[0]), Token.unwrap(token0Sorted));
        assertEq(Token.unwrap(pair.tokens[1]), Token.unwrap(token1Sorted));

        vm.stopPrank();
    }

    /// @dev test can list all supported tokens
    function testShouldBeAbleToListAllSupportedTokens() public {
        vm.startPrank(admin);
        carbonController.createPair(token0, token1);
        Token[2][] memory pairs = carbonController.pairs();

        (Token token0Sorted, Token token1Sorted) = sortTokens(token0, token1);
        assertEq(pairs.length, 1);
        assertEq(Token.unwrap(pairs[0][0]), Token.unwrap(token0Sorted));
        assertEq(Token.unwrap(pairs[0][1]), Token.unwrap(token1Sorted));

        vm.stopPrank();
    }

    /// @dev test that an attempt to fetch a pair by an id which doesnt exist reverts
    function testShouldRevertWhenTryingToFetchAPairByAnIdWhichDoesntExist() public {
        TestPairs testPairs = new TestPairs();
        testPairs.createPairTest(token0, token1);
        vm.expectRevert(Pairs.PairDoesNotExist.selector);
        testPairs.pairByIdTest(2);
    }

    /// @dev helper function to sort tokens in ascending order
    function sortTokens(Token token0, Token token1) private pure returns (Token token0Sorted, Token token1Sorted) {
        if (Token.unwrap(token0) < Token.unwrap(token1)) {
            return (token0, token1);
        } else {
            return (token1, token0);
        }
    }
}
