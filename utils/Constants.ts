import { toPPM } from './Types';
import { ethers } from 'ethers';

const {
    constants: { AddressZero, MaxUint256 }
} = ethers;

export enum DeploymentNetwork {
    Mainnet = 'mainnet',
    Rinkeby = 'rinkeby',
    Hardhat = 'hardhat',
    Tenderly = 'tenderly'
}

export const MAX_UINT256 = MaxUint256;
export const ZERO_BYTES = '0x';
export const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
export const ZERO_ADDRESS = AddressZero;
export const ZERO_FRACTION = { n: 0, d: 1 };
export const PPM_RESOLUTION = 1_000_000;

export const DEFAULT_TRADING_FEE_PPM = toPPM(0.15);

export enum ControllerType {
    Standard = 1
}
