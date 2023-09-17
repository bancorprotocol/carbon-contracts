// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Pairs, Pair } from "../carbon/Pairs.sol";
import { Token } from "../token/Token.sol";

contract TestPairs is Pairs {
    function pairByIdTest(uint128 pairId) external view returns (Pair memory) {
        return _pairById(pairId);
    }

    function createPairTest(Token token0, Token token1) external returns (Pair memory) {
        return _createPair(token0, token1);
    }
}
