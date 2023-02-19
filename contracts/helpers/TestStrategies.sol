// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import { Strategies } from "../carbon/Strategies.sol";

contract TestStrategies is Strategies {
    // solhint-disable var-name-mixedcase

    function tradeBySourceAmount(uint256 x, uint256 y, uint256 z, uint256 A, uint256 B) external pure returns (uint128) {
        return _tradeTargetAmount(x, y, z, A, B);
    }

    function tradeByTargetAmount(uint256 x, uint256 y, uint256 z, uint256 A, uint256 B) external pure returns (uint128) {
        return _tradeSourceAmount(x, y, z, A, B);
    }

    // solhint-enable var-name-mixedcase
}
