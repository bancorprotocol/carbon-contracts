// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ExpDecayMath } from "../utility/ExpDecayMath.sol";

contract TestExpDecayMath {
    function calcExpDecay(uint256 amount, uint32 timeElapsed, uint32 halfLife) external pure returns (uint256) {
        return ExpDecayMath.calcExpDecay(amount, timeElapsed, halfLife);
    }
}
