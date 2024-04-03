// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Fraction } from "./Fraction.sol";
import { MathEx } from "./MathEx.sol";

/**
 * @dev This library supports the calculation of exponential price decay
 */
library ExpDecayMath {
    /**
     * @dev returns the amount required for a token after a given time period since trading has been enabled
     *
     * the returned value is calculated as `amount / 2 ^ (timeElapsed / halfLife)`
     * note that the input value to this function is limited by `timeElapsed / halfLife <= 128`
     */
    function calcExpDecay(uint256 amount, uint32 timeElapsed, uint32 halfLife) internal pure returns (uint256) {
        uint256 integerPart = timeElapsed / halfLife;
        uint256 fractionPart = timeElapsed % halfLife;
        Fraction memory input = Fraction({ n: fractionPart , d: halfLife });
        Fraction memory output = MathEx.exp2(input);
        return MathEx.mulDivF(amount, output.d, output.n * 2 ** integerPart);
    }
}
