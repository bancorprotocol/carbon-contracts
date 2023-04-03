// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Pairs, Pair } from "../carbon/Pairs.sol";
import { Token } from "../token/Token.sol";

contract TestPairs is Pairs {
    function testPairById(uint128 pairId) external view returns (Pair memory) {
        return _pairById(pairId);
    }

    function testCreatePair(Token token0, Token token1) external returns (Pair memory) {
        return _createPair(token0, token1);
    }
}
