import { NamedAccounts } from './data/named-accounts';
import { DeploymentNetwork } from './utils/Constants';
import './test/Setup';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-solhint';
import '@nomiclabs/hardhat-waffle';
import '@tenderly/hardhat-tenderly';
import '@typechain/hardhat';
import 'dotenv/config';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-deploy';
import 'hardhat-storage-layout';
import 'hardhat-watcher';
import { HardhatUserConfig } from 'hardhat/config';
import { MochaOptions } from 'mocha';
import 'solidity-coverage';
import chainIds from './utils/chainIds.json';

interface EnvOptions {
    ETHEREUM_PROVIDER_URL?: string;
    MANTLE_PROVIDER_URL?: string;
    BASE_PROVIDER_URL?: string;
    ARBITRUM_PROVIDER_URL?: string;
    ETHEREUM_SEPOLIA_PROVIDER_URL?: string;
    TENDERLY_TESTNET_PROVIDER_URL?: string;
    MAINNET_ETHERSCAN_API_KEY?: string;
    SEPOLIA_ETHERSCAN_API_KEY?: string;
    BASESCAN_API_KEY?: string;
    ARBISCAN_API_KEY?: string;
    GAS_PRICE?: number | 'auto';
    NIGHTLY?: boolean;
    PROFILE?: boolean;
    TENDERLY_FORK_ID?: string;
    TENDERLY_PROJECT?: string;
    TENDERLY_TEST_PROJECT?: string;
    TENDERLY_USERNAME?: string;
    TENDERLY_NETWORK_NAME?: string;
}

const {
    ETHEREUM_PROVIDER_URL = '',
    BASE_PROVIDER_URL = '',
    MANTLE_PROVIDER_URL = '',
    ARBITRUM_PROVIDER_URL = '',
    ETHEREUM_SEPOLIA_PROVIDER_URL = '',
    TENDERLY_TESTNET_PROVIDER_URL = '',
    MAINNET_ETHERSCAN_API_KEY = '',
    SEPOLIA_ETHERSCAN_API_KEY = '',
    BASESCAN_API_KEY = '',
    ARBISCAN_API_KEY = '',
    GAS_PRICE: gasPrice = 'auto',
    TENDERLY_FORK_ID = '',
    TENDERLY_PROJECT = '',
    TENDERLY_TEST_PROJECT = '',
    TENDERLY_USERNAME = '',
    TENDERLY_NETWORK_NAME = DeploymentNetwork.Mainnet
}: EnvOptions = process.env as any as EnvOptions;

const mochaOptions = (): MochaOptions => {
    let timeout = 600000;
    let grep = '';
    let reporter;
    let invert = false;

    return {
        timeout,
        color: true,
        bail: true,
        grep,
        invert,
        reporter
    };
};

const config: HardhatUserConfig = {
    networks: {
        [DeploymentNetwork.Hardhat]: {
            accounts: {
                count: 20,
                accountsBalance: '10000000000000000000000000000000000000000000000'
            },
            allowUnlimitedContractSize: true,
            saveDeployments: false,
            live: false
        },
        [DeploymentNetwork.Mainnet]: {
            chainId: 1,
            url: ETHEREUM_PROVIDER_URL,
            gasPrice,
            saveDeployments: true,
            live: true,
            verify: {
                etherscan: {
                    apiKey: MAINNET_ETHERSCAN_API_KEY
                }
            }
        },
        [DeploymentNetwork.Mantle]: {
            chainId: chainIds[DeploymentNetwork.Mantle],
            url: MANTLE_PROVIDER_URL,
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Mantle}`]
        },
        [DeploymentNetwork.Base]: {
            chainId: chainIds[DeploymentNetwork.Base],
            url: BASE_PROVIDER_URL,
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Base}`],
            verify: {
                etherscan: {
                    apiKey: BASESCAN_API_KEY
                }
            }
        },
        [DeploymentNetwork.Arbitrum]: {
            chainId: chainIds[DeploymentNetwork.Arbitrum],
            url: ARBITRUM_PROVIDER_URL,
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Arbitrum}`],
            verify: {
                etherscan: {
                    apiKey: ARBISCAN_API_KEY
                }
            }
        },
        [DeploymentNetwork.Sepolia]: {
            chainId: chainIds[DeploymentNetwork.Sepolia],
            url: ETHEREUM_SEPOLIA_PROVIDER_URL,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Sepolia}`],
            verify: {
                etherscan: {
                    apiKey: SEPOLIA_ETHERSCAN_API_KEY
                }
            }
        },
        [DeploymentNetwork.Tenderly]: {
            chainId: Number(chainIds[TENDERLY_NETWORK_NAME as keyof typeof chainIds]),
            url: `https://rpc.tenderly.co/fork/${TENDERLY_FORK_ID}`,
            autoImpersonate: true,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${TENDERLY_NETWORK_NAME}`]
        },
        [DeploymentNetwork.TenderlyTestnet]: {
            chainId: Number(chainIds[TENDERLY_NETWORK_NAME as keyof typeof chainIds]),
            url: TENDERLY_TESTNET_PROVIDER_URL,
            autoImpersonate: true,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${TENDERLY_NETWORK_NAME}`]
        }
    },

    paths: {
        deploy: ['deploy/scripts']
    },

    tenderly: {
        forkNetwork: chainIds[TENDERLY_NETWORK_NAME as keyof typeof chainIds].toString(),
        project: TENDERLY_PROJECT || TENDERLY_TEST_PROJECT,
        username: TENDERLY_USERNAME
    },

    solidity: {
        compilers: [
            {
                version: '0.8.19',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 2000
                    },
                    metadata: {
                        bytecodeHash: 'none'
                    },
                    outputSelection: {
                        '*': {
                            '*': ['storageLayout'] // Enable slots, offsets and types of the contract's state variables
                        }
                    }
                }
            }
        ]
    },

    dependencyCompiler: {
        paths: [
            '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
            'hardhat-deploy/solc_0.8/proxy/OptimizedTransparentUpgradeableProxy.sol'
        ]
    },

    namedAccounts: NamedAccounts,

    external: {
        deployments: {
            [DeploymentNetwork.Mainnet]: [`deployments/${DeploymentNetwork.Mainnet}`],
            [DeploymentNetwork.Mantle]: [`deployments/${DeploymentNetwork.Mantle}`],
            [DeploymentNetwork.Base]: [`deployments/${DeploymentNetwork.Base}`],
            [DeploymentNetwork.Arbitrum]: [`deployments/${DeploymentNetwork.Arbitrum}`],
            [DeploymentNetwork.Tenderly]: [`deployments/${DeploymentNetwork.Tenderly}`],
            [DeploymentNetwork.TenderlyTestnet]: [`deployments/${DeploymentNetwork.TenderlyTestnet}`]
        }
    },

    contractSizer: {
        alphaSort: true,
        runOnCompile: false,
        disambiguatePaths: false
    },

    watcher: {
        test: {
            tasks: [{ command: 'test' }],
            files: ['./test/**/*', './contracts/**/*', './deploy/**/*'],
            verbose: true
        }
    },

    mocha: mochaOptions()
};

export default config;
