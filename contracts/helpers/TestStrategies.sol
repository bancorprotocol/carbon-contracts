// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Strategies, Order } from "../carbon/Strategies.sol";

contract TestStrategies is Strategies {
    function tradeBySourceAmount(Order memory order, uint128 amount) external pure returns (uint128) {
        (, uint128 targetAmount) = _singleTradeActionSourceAndTargetAmounts(order, amount, false);
        return targetAmount;
    }

    function tradeByTargetAmount(Order memory order, uint128 amount) external pure returns (uint128) {
        (uint128 sourceAmount, ) = _singleTradeActionSourceAndTargetAmounts(order, amount, true);
        return sourceAmount;
    }
}
