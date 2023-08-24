// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Token } from "../token/Token.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract MockUniswapV3Oracle {
    using Address for address;

    // fallback mock price with 18 decimals precision for pools which aren't set
    uint256 private immutable _price;

    // uniswap v3 factory
    IUniswapV3Factory private immutable _factory;

    // mock prices with 18 decimals precision
    mapping(address pool => uint256 price) private poolPrices;

    constructor(uint256 price, IUniswapV3Factory factory) {
        _price = price;
        _factory = factory;
    }

    receive() external payable {}

    function setPriceForPool(Token token0, Token token1, uint24 fee, uint256 price) external {
        address pool = _factory.getPool(Token.unwrap(token0), Token.unwrap(token1), fee);
        poolPrices[pool] = price;
    }

    /// @notice Returns a quote, based on the given tokens and amount, by querying only the specified fee tiers
    /// @dev Will revert if the pair does not have a pool for one of the given fee tiers, or if one of the pools
    /// is not prepared/configured correctly for the given period
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @param feeTiers The fee tiers to consider when calculating the quote
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    /// @return queriedPools The pools that were queried to calculate the quote
    function quoteSpecificFeeTiersWithTimePeriod(
        uint128 baseAmount,
        address baseToken,
        address quoteToken,
        uint24[] calldata feeTiers,
        uint32 //period
    ) external view returns (uint256 quoteAmount, address[] memory queriedPools) {
        address[] memory pools = _getPoolsForTiers(baseToken, quoteToken, feeTiers);
        uint256 price = poolPrices[pools[0]];
        if (price == 0) {
            price = _price;
        }
        quoteAmount = (baseAmount * price) / 1e18;
        return (quoteAmount, pools);
    }

    /// @notice Takes a pair and some fee tiers, and returns all pools that match those tiers
    /// @param _tokenA One of the pair's tokens
    /// @param _tokenB The other of the pair's tokens
    /// @param _feeTiers The fee tiers to consider when searching for the pair's pools
    /// @return _pools The pools for the given pair and fee tiers
    function _getPoolsForTiers(
        address _tokenA,
        address _tokenB,
        uint24[] memory _feeTiers
    ) internal view virtual returns (address[] memory _pools) {
        _pools = new address[](_feeTiers.length);
        uint256 _validPools;
        for (uint256 i; i < _feeTiers.length; i++) {
            address _pool = _factory.getPool(_tokenA, _tokenB, _feeTiers[i]);
            if (Address.isContract(_pool)) {
                _pools[_validPools++] = _pool;
            }
        }

        _resizeArray(_pools, _validPools);
    }

    function _resizeArray(address[] memory _array, uint256 _amountOfValidElements) internal pure {
        // If all elements are valid, then nothing to do here
        if (_array.length == _amountOfValidElements) return;

        // solhint-disable no-inline-assembly
        // If not, then resize the array
        assembly {
            mstore(_array, _amountOfValidElements)
        }
    }
}
