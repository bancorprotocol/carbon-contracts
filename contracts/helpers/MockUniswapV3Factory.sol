// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Token } from "../token/Token.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { MockUniswapV3Pool } from "./MockUniswapV3Pool.sol";

contract MockUniswapV3Factory {
    // mapping of pools
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
    // fee mapping to tick spacing
    mapping(uint24 => int24) public feeAmountTickSpacing;

    constructor() {
        feeAmountTickSpacing[500] = 10;
        feeAmountTickSpacing[3000] = 60;
        feeAmountTickSpacing[10000] = 200;
    }

    /**
     * @dev creates a pool with two tokens and fee
     */
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        require(tokenA != tokenB, "Tokens must be different");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Token 0 cannot be address 0x0");
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0, "Tick spacing cannot be 0");
        require(getPool[token0][token1][fee] == address(0), "The pool already exists");
        pool = address(new MockUniswapV3Pool(token0, token1, fee));
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
    }

    /**
     * @dev enable a fee
     */
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public {
        require(fee < 1000000, "Fee should be < 1000000");
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384, "Tick spacing should be correct");
        require(feeAmountTickSpacing[fee] == 0, "Fee shouldn't be initialized");

        feeAmountTickSpacing[fee] = tickSpacing;
    }
}
