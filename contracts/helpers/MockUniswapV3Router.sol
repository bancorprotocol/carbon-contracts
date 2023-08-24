// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Token } from "../token/Token.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract MockUniswapV3Router {
    // uniswap v3 factory address
    IUniswapV3Factory private immutable _factory;

    // what amount is added or subtracted to/from the input amount on swap
    uint private _outputAmount;

    // true if the gain amount is added to the swap input, false if subtracted
    bool private _profit;

    constructor(uint outputAmount, bool profit, IUniswapV3Factory factory) {
        _outputAmount = outputAmount;
        _profit = profit;
        _factory = factory;
    }

    receive() external payable {}

    /**
     * @dev set profit and output amount
     */
    function setProfitAndOutputAmount(bool newProfit, uint256 newOutputAmount) external {
        _profit = newProfit;
        _outputAmount = newOutputAmount;
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams memory params) external payable returns (uint256) {
        require(_factory.getPool(params.tokenIn, params.tokenOut, params.fee) != address(0), "Pool does not exist");
        return
            mockSwap(
                Token.wrap(params.tokenIn),
                Token.wrap(params.tokenOut),
                params.amountIn,
                msg.sender,
                params.deadline,
                params.amountOutMinimum
            );
    }

    function mockSwap(
        Token sourceToken,
        Token targetToken,
        uint256 amount,
        address trader,
        uint deadline,
        uint minTargetAmount
    ) private returns (uint256) {
        require(deadline >= block.timestamp, "Swap timeout");
        // withdraw source amount
        sourceToken.safeTransferFrom(trader, address(this), amount);

        // transfer target amount
        // receive _outputAmount tokens per swap
        uint targetAmount;
        if (_profit) {
            targetAmount = amount + _outputAmount;
        } else {
            targetAmount = amount - _outputAmount;
        }
        require(targetAmount >= minTargetAmount, "Too little received");
        targetToken.safeTransfer(trader, targetAmount);
        return targetAmount;
    }
}
