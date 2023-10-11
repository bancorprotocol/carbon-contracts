// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { TestERC20Token } from "./TestERC20Token.sol";

contract TestBNT is TestERC20Token {
    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply
    ) TestERC20Token(name, symbol, totalSupply) {
        _mint(msg.sender, totalSupply);
    }

    // triggered when the total supply is decreased
    event Destruction(uint256 _amount);

    function transfer(address _to, uint256 _value) public override(ERC20) returns (bool success) {
        assert(super.transfer(_to, _value));

        // transferring to the contract address destroys tokens
        if (_to == address(this)) {
            _burn(address(this), _value);
            emit Destruction(_value);
        }

        return true;
    }

    function issue(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function destroy(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function owner() external pure returns (address) {
        return address(0);
    }

    function transferOwnership(address newOwner) external {}

    function acceptOwnership() external {}
}
