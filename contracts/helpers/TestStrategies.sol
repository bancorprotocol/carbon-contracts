// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Strategies, Order } from "../carbon/Strategies.sol";

contract TestStrategies is Strategies {
    function tradeBySourceAmount(Order memory order, uint128 amount) external pure returns (uint128) {
        return _singleTradeActionSourceAndTargetAmounts(order, amount, false).targetAmount;
    }

    function tradeByTargetAmount(Order memory order, uint128 amount) external pure returns (uint128) {
        return _singleTradeActionSourceAndTargetAmounts(order, amount, true).sourceAmount;
    }
}
