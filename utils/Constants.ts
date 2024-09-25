import Decimal from 'decimal.js';
import { toPPM } from './Types';
import { ethers } from 'ethers';

const {
    constants: { AddressZero, MaxUint256 }
} = ethers;

export enum MainnetNetwork {
    Arbitrum = 'arbitrum',
    Astar = 'astar',
    Aurora = 'aurora',
    Avalanche = 'avalanche',
    Base = 'base',
    BSC = 'bsc',
    Blast = 'blast',
    Canto = 'canto',
    Celo = 'celo',
    Cronos = 'cronos',
    Fantom = 'fantom',
    Fusion = 'fusion',
    Gnosis = 'gnosis',
    Hedera = 'hedera',
    Kava = 'kava',
    Klaytn = 'klaytn',
    Linea = 'linea',
    Mainnet = 'mainnet',
    Manta = 'manta',
    Mantle = 'mantle',
    Metis = 'metis',
    Mode = 'mode',
    Moonbeam = 'moonbeam',
    Optimism = 'optimism',
    Polygon = 'polygon',
    PulseChain = 'pulsechain',
    Rootstock = 'rootstock',
    Scroll = 'scroll',
    Telos = 'telos',
    ZkSync = 'zksync',
    Sei = 'sei'
}

export enum TestnetNetwork {
    Hardhat = 'hardhat',
    Sepolia = 'sepolia',
    Tenderly = 'tenderly',
    TenderlyTestnet = 'tenderly-testnet'
}

export const DeploymentNetwork = {
    ...MainnetNetwork,
    ...TestnetNetwork
};

export const EXP2_INPUT_TOO_HIGH = new Decimal(16).div(new Decimal(2).ln());
export const MAX_UINT256 = MaxUint256;
export const MAX_UINT128 = '340282366920938463463374607431768211455';
export const ZERO_BYTES = '0x';
export const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
export const ZERO_ADDRESS = AddressZero;
export const NATIVE_TOKEN_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const ZERO_FRACTION = { n: 0, d: 1 };
export const PPM_RESOLUTION = 1_000_000;
export const VOUCHER_URI = 'ipfs://QmUyDUzQtwAhMB1hrYaQAqmRTbgt9sUnwq11GeqyzzSuqn';

export const DEFAULT_TRADING_FEE_PPM = toPPM(0.2);

// strategy update reasons
export const STRATEGY_UPDATE_REASON_EDIT = 0;
export const STRATEGY_UPDATE_REASON_TRADE = 1;

export enum ControllerType {
    Standard = 1
}
