// SPDX-License-Identifier: SEE LICENSE IN LICENSE
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

    function isValidRate(uint256 rate) external pure returns (bool) {
        return _validRate(rate);
    }

    function expandedRate(uint256 rate) external pure returns (uint256) {
        return _expandRate(rate);
    }
}
