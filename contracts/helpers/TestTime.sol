// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Time } from "../utility/Time.sol";

contract TestTime is Time {
    uint32 private _currentTime = 1;

    function setTime(uint32 newTime) external {
        _currentTime = newTime;
    }

    function currentTime() external view returns (uint32) {
        return _currentTime;
    }

    function realTime() external view returns (uint32) {
        return super._time();
    }

    function _time() internal view virtual override returns (uint32) {
        return _currentTime;
    }
}
