// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ExpDecayMath } from "../utility/ExpDecayMath.sol";

contract TestExpDecayMath {
    function calcExpDecay(uint256 ethAmount, uint32 timeElapsed, uint32 halfLife) external pure returns (uint256) {
        return ExpDecayMath.calcExpDecay(ethAmount, timeElapsed, halfLife);
    }
}
