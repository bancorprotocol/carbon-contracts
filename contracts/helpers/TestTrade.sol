// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Trade } from "../utility/Trade.sol";

contract TradeTest {
    function calcTargetAmount(
        Trade.GradientType gradientType,
        uint64 initialRate,
        uint32 multiFactor,
        uint32 timeElapsed,
        uint256 sourceAmount
    ) external pure returns (uint256) {
        return Trade.calcTargetAmount(gradientType, initialRate, multiFactor, timeElapsed, sourceAmount);
    }

    function calcSourceAmount(
        Trade.GradientType gradientType,
        uint64 initialRate,
        uint32 multiFactor,
        uint32 timeElapsed,
        uint256 targetAmount
    ) external pure returns (uint256) {
        return Trade.calcTargetAmount(gradientType, initialRate, multiFactor, timeElapsed, targetAmount);
    }
}
