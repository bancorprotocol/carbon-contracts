// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

/**
 * @dev restrict delegation
 */
abstract contract OnlyProxyDelegate {
    address private immutable _proxy;

    error UnknownDelegator();

    constructor(address proxy) {
        _proxy = proxy;
    }

    modifier onlyProxyDelegate() {
        _onlyProxyDelegate();

        _;
    }

    function _onlyProxyDelegate() internal view {
        if (address(this) != _proxy) {
            revert UnknownDelegator();
        }
    }
}
