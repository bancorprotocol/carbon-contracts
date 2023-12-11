// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract TestERC20FeeOnTransfer is ERC20Permit {
    uint8 private _decimals = 18;
    bool private _feeEnabled = true;
    uint256 private _feeDivisor = 1000; // 1000 = 0.1%, 100 = 1%
    bool private _positiveFee = true;

    constructor(string memory name, string memory symbol, uint256 totalSupply) ERC20(name, symbol) ERC20Permit(name) {
        _mint(msg.sender, totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function updateDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    /**
     * @dev set if fee is enabled
     */
    function setFeeEnabled(bool enabled) external {
        _feeEnabled = enabled;
    }

    /**
     * @dev set fee divisor to take
     */
    function setFeeDivisor(uint256 feeDivisor) external {
        _feeDivisor = feeDivisor;
    }

    /**
     * @dev set fee side - positive means contract takes fee, negative means contract transfers more tokens
     */
    function setFeeSide(bool positiveFee) external {
        _positiveFee = positiveFee;
    }

    /**
     * @dev overriden transferFrom function which takes tax from every transfer
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!_feeEnabled) {
            return super.transferFrom(from, to, amount);
        } else {
            uint256 feeAmount = amount / _feeDivisor;
            uint256 transferAmount = _positiveFee ? amount - feeAmount : amount + feeAmount;
            return super.transferFrom(from, to, transferAmount);
        }
    }
}
