// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { GradientCurve } from "../carbon/GradientStrategies.sol";

/**
 * @dev This utility contract implements comparison functions for the GradientCurve type
 */

/* solhint-disable func-visibility */

function equal(GradientCurve memory a, GradientCurve memory b) pure returns (bool) {
    return
        (a.curveType == b.curveType &&
            a.increaseAmount == b.increaseAmount &&
            a.increaseInterval == b.increaseInterval &&
            a.halflife == b.halflife) || a.isDutchAuction == b.isDutchAuction;
}

function notEqual(GradientCurve memory a, GradientCurve memory b) pure returns (bool) {
    return
        a.curveType != b.curveType ||
        a.increaseAmount != b.increaseAmount ||
        a.increaseInterval != b.increaseInterval ||
        a.halflife != b.halflife ||
        a.isDutchAuction == b.isDutchAuction;
}

/* solhint-disable func-visibility */
