// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ICarbonVortex } from "../vortex/interfaces/ICarbonVortex.sol";
import { Token } from "../token/Token.sol";

/**
 * @dev contract which attempts to re-enter CarbonVortex
 */
contract TestReenterCarbonVortex {
    ICarbonVortex private immutable _carbonVortex;

    constructor(ICarbonVortex carbonVortexInit) {
        _carbonVortex = carbonVortexInit;
    }

    receive() external payable {
        Token[] memory tokens = new Token[](0);

        // re-enter execute, reverting the tx
        _carbonVortex.execute(tokens);
    }

    function tryReenterCarbonVortex(Token[] calldata tokens) external {
        _carbonVortex.execute(tokens);
    }
}
