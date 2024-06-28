// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import { OptimizedTransparentUpgradeableProxy } from "hardhat-deploy/solc_0.8/proxy/OptimizedTransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @dev Contract used to load the ProxyAdmin and OptimizedTransparentUpgradeableProxy contracts
 * @dev workaround for tenderly verification issues with ethers-v5:
 * @dev https://docs.tenderly.co/contract-verification/hardhat-proxy-contracts#load-the-proxy-contracts
 */
abstract contract OptimizedTransparentUpgradeableProxyAccess is OptimizedTransparentUpgradeableProxy {}
abstract contract ProxyAdminAccess is ProxyAdmin {}
