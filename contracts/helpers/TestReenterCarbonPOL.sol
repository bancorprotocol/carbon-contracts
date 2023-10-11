// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ICarbonPOL } from "../pol/interfaces/ICarbonPOL.sol";
import { Token } from "../token/Token.sol";

/**
 * @dev contract which attempts to re-enter CarbonPOL
 */
contract TestReenterCarbonPOL {
    ICarbonPOL private immutable _carbonPOL;
    Token private immutable _token;

    constructor(ICarbonPOL carbonPOLInit, Token tokenInit) {
        _carbonPOL = carbonPOLInit;
        _token = tokenInit;
    }

    receive() external payable {
        uint128 amount = 1e18;

        // re-enter trade, reverting the tx
        _carbonPOL.trade{ value: msg.value }(_token, amount);
    }

    function tryReenterCarbonPOL(uint128 amount) external payable {
        _carbonPOL.trade{ value: msg.value }(_token, amount);
    }
}
