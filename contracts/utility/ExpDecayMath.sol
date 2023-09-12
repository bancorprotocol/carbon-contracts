// SPDX-License-Identifier: BUSL-1.1
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
     * note that because the exponentiation function is limited to an input of up to (and excluding)
     * 16 / ln 2, the input value to this function is limited by `timeElapsed / halfLife < 16 / ln 2`
     */
    function calcExpDecay(uint256 amount, uint32 timeElapsed, uint32 halfLife) internal pure returns (uint256) {
        Fraction memory input = Fraction({ n: timeElapsed, d: halfLife });
        Fraction memory output = MathEx.exp2(input);
        return MathEx.mulDivF(amount, output.d, output.n);
    }
}
