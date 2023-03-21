// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/**
 * @dev restrict delegation
 */
abstract contract OnlyProxyDelegate {
    address private immutable _proxy;

    error UnknownDelegator();
    error UnsetDelegator();

    constructor(address proxy) {
        _proxy = proxy;
    }

    modifier onlyProxyDelegate() {
        _onlyProxyDelegate();

        _;
    }

    function _onlyProxyDelegate() internal view {
        if (_proxy == address(0)) {
            revert UnsetDelegator();
        }
        if (address(this) != _proxy) {
            revert UnknownDelegator();
        }
    }
}
