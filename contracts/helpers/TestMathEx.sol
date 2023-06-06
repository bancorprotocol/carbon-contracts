// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { MathEx } from "../utility/MathEx.sol";

contract TestMathEx {
    function mulDivF(uint256 x, uint256 y, uint256 z) external pure returns (uint256) {
        return MathEx.mulDivF(x, y, z);
    }

    function mulDivC(uint256 x, uint256 y, uint256 z) external pure returns (uint256) {
        return MathEx.mulDivC(x, y, z);
    }

    function minFactor(uint256 x, uint256 y) external pure returns (uint256) {
        return MathEx.minFactor(x, y);
    }
}
