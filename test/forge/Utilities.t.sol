// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

contract Utilities is Test {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    /// @dev get next user address
    function getNextUserAddress() public returns (address payable) {
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    /// @dev create users with 100 ETH balance each
    function createUsers(uint256 userNum) public returns (address payable[] memory) {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = getNextUserAddress();
            vm.deal(user, 1000000 ether);
            users[i] = user;
        }

        return users;
    }
}
