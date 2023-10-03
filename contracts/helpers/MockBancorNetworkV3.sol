// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Token } from "../token/Token.sol";

contract MockBancorNetworkV3 {
    // the address that represents the native token reserve
    address private constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private immutable _bnt;

    // what amount is added or subtracted to/from the input amount on swap
    uint256 private immutable _outputAmount;

    // true if the gain amount is added to the swap input, false if subtracted
    bool private immutable _profit;

    // mapping for tokens tradeable on v3
    mapping(Token => address) public collectionByPool;

    error InsufficientFlashLoanReturn();
    error NotWhitelisted();
    error ZeroValue();

    constructor(address bnt, uint256 outputAmount, bool profit) {
        _bnt = bnt;
        _outputAmount = outputAmount;
        _profit = profit;
    }

    receive() external payable {}

    /**
     * @dev set collection by pool
     */
    function setCollectionByPool(Token token) external {
        collectionByPool[token] = Token.unwrap(token);
    }

    /**
     * @dev reset collection by pool
     */
    function resetCollectionByPool(Token token) external {
        collectionByPool[token] = address(0);
    }

    /**
     * Bancor v3 trade
     */
    function tradeBySourceAmount(
        Token sourceToken,
        Token targetToken,
        uint256 sourceAmount,
        uint256 minReturnAmount,
        uint256 deadline,
        address /* beneficiary */
    ) external payable returns (uint256) {
        if (minReturnAmount == 0) {
            revert ZeroValue();
        }
        return mockSwap(sourceToken, targetToken, sourceAmount, msg.sender, deadline, minReturnAmount);
    }

    function mockSwap(
        Token sourceToken,
        Token targetToken,
        uint256 amount,
        address trader,
        uint256 deadline,
        uint256 minTargetAmount
    ) private returns (uint256) {
        /* solhint-disable custom-errors */
        require(deadline >= block.timestamp, "Swap timeout");
        // withdraw source amount
        sourceToken.safeTransferFrom(trader, address(this), amount);

        // transfer target amount
        // receive _outputAmount tokens per swap
        uint256 targetAmount;
        if (_profit) {
            targetAmount = amount + _outputAmount;
        } else {
            targetAmount = amount - _outputAmount;
        }
        require(targetAmount >= minTargetAmount, "InsufficientTargetAmount");
        targetToken.safeTransfer(trader, targetAmount);
        return targetAmount;
        /* solhint-enable custom-errors */
    }
}
