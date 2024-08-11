// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Trade } from "../utility/Trade.sol";

contract TestTrade {
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

    function calcCurrentRate(
        Trade.GradientType gradientType,
        uint64 initialRate,
        uint32 multiFactor,
        uint32 timeElapsed
    ) external pure returns (uint256, uint256) {
        return Trade.calcCurrentRate(gradientType, initialRate, multiFactor, timeElapsed);
    }

    function exp(uint256 x) external pure returns (uint256) {
        return Trade.exp(x);
    }
}
