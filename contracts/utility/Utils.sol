// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { PPM_RESOLUTION, PPB_RESOLUTION } from "./Constants.sol";
import { Token } from "../token/Token.sol";

error AccessDenied();
error InvalidAddress();
error InvalidFee();
error ZeroValue();
error InvalidIndices();
error InvalidValue();
error InvalidPeriod();

/**
 * @dev common utilities
 */
abstract contract Utils {
    using Address for address payable;

    // verifies that a value is greater than zero
    modifier greaterThanZero(uint256 value) {
        _greaterThanZero(value);

        _;
    }

    // error message binary size optimization
    function _greaterThanZero(uint256 value) internal pure {
        if (value == 0) {
            revert ZeroValue();
        }
    }

    // validates an address - currently only checks that it isn't null
    modifier validAddress(address addr) {
        _validAddress(addr);

        _;
    }

    // error message binary size optimization
    function _validAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert InvalidAddress();
        }
    }

    // ensures that the fee is valid
    modifier validFee(uint32 fee) {
        _validFee(fee);

        _;
    }

    // error message binary size optimization
    function _validFee(uint32 fee) internal pure {
        if (fee > PPM_RESOLUTION) {
            revert InvalidFee();
        }
    }

    // ensures that the value is valid
    modifier validValue(uint32 value) {
        _validValue(value);

        _;
    }

    // error message binary size optimization
    function _validValue(uint32 value) internal pure {
        if (value > PPB_RESOLUTION) {
            revert InvalidValue();
        }
    }

    // ensures that the period is valid
    modifier validPeriod(uint32 period) {
        _validPeriod(period);

        _;
    }

    // error message binary size optimization
    function _validPeriod(uint32 period) internal pure {
        if (period == 0) {
            revert InvalidPeriod();
        }
    }
}
