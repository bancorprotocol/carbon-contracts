// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { OnlyProxyDelegate } from "../utility/OnlyProxyDelegate.sol";

contract TestOnlyProxyDelegate is OnlyProxyDelegate {
    constructor(address delegator) OnlyProxyDelegate(delegator) {}

    function testOnlyProxyDelegate() external view onlyProxyDelegate returns (bool) {
        return true;
    }
}
