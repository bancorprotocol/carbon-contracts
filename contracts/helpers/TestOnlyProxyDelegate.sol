// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { OnlyProxyDelegate } from "../utility/OnlyProxyDelegate.sol";

contract TestOnlyProxyDelegate is OnlyProxyDelegate {
    constructor(address delegator) OnlyProxyDelegate(delegator) {}

    function testOnlyProxyDelegate() external view onlyProxyDelegate returns (bool) {
        return true;
    }
}
