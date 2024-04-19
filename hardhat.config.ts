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
import rpcUrls from './utils/rpcUrls.json';

interface EnvOptions {
    TENDERLY_TESTNET_PROVIDER_URL?: string;
    GAS_PRICE?: number | 'auto';
    NIGHTLY?: boolean;
    PROFILE?: boolean;
    VERIFY_API_KEY?: string;
    TENDERLY_FORK_ID?: string;
    TENDERLY_PROJECT?: string;
    TENDERLY_TEST_PROJECT?: string;
    TENDERLY_USERNAME?: string;
    TENDERLY_NETWORK_NAME?: string;
}

const {
    TENDERLY_TESTNET_PROVIDER_URL = '',
    VERIFY_API_KEY = '',
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
            chainId: chainIds[DeploymentNetwork.Mainnet],
            url: rpcUrls[DeploymentNetwork.Mainnet],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Mainnet}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Optimism]: {
            chainId: chainIds[DeploymentNetwork.Optimism],
            url: rpcUrls[DeploymentNetwork.Optimism],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Optimism}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Cronos]: {
            chainId: chainIds[DeploymentNetwork.Cronos],
            url: rpcUrls[DeploymentNetwork.Cronos],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Cronos}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Rootstock]: {
            chainId: chainIds[DeploymentNetwork.Rootstock],
            url: rpcUrls[DeploymentNetwork.Rootstock],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Rootstock}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Telos]: {
            chainId: chainIds[DeploymentNetwork.Telos],
            url: rpcUrls[DeploymentNetwork.Telos],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Telos}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.BSC]: {
            chainId: chainIds[DeploymentNetwork.BSC],
            url: rpcUrls[DeploymentNetwork.BSC],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.BSC}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Gnosis]: {
            chainId: chainIds[DeploymentNetwork.Gnosis],
            url: rpcUrls[DeploymentNetwork.Gnosis],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Gnosis}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Polygon]: {
            chainId: chainIds[DeploymentNetwork.Polygon],
            url: rpcUrls[DeploymentNetwork.Polygon],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Polygon}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Fantom]: {
            chainId: chainIds[DeploymentNetwork.Fantom],
            url: rpcUrls[DeploymentNetwork.Fantom],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Fantom}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Hedera]: {
            chainId: chainIds[DeploymentNetwork.Hedera],
            url: rpcUrls[DeploymentNetwork.Hedera],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Hedera}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.ZkSync]: {
            chainId: chainIds[DeploymentNetwork.ZkSync],
            url: rpcUrls[DeploymentNetwork.ZkSync],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.ZkSync}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.PulseChain]: {
            chainId: chainIds[DeploymentNetwork.PulseChain],
            url: rpcUrls[DeploymentNetwork.PulseChain],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.PulseChain}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Astar]: {
            chainId: chainIds[DeploymentNetwork.Astar],
            url: rpcUrls[DeploymentNetwork.Astar],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Astar}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Metis]: {
            chainId: chainIds[DeploymentNetwork.Metis],
            url: rpcUrls[DeploymentNetwork.Metis],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Metis}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Moonbeam]: {
            chainId: chainIds[DeploymentNetwork.Moonbeam],
            url: rpcUrls[DeploymentNetwork.Moonbeam],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Moonbeam}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Kava]: {
            chainId: chainIds[DeploymentNetwork.Kava],
            url: rpcUrls[DeploymentNetwork.Kava],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Kava}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Mantle]: {
            chainId: chainIds[DeploymentNetwork.Mantle],
            url: rpcUrls[DeploymentNetwork.Mantle],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Mantle}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Canto]: {
            chainId: chainIds[DeploymentNetwork.Canto],
            url: rpcUrls[DeploymentNetwork.Canto],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Canto}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Klaytn]: {
            chainId: chainIds[DeploymentNetwork.Klaytn],
            url: rpcUrls[DeploymentNetwork.Klaytn],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Klaytn}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Base]: {
            chainId: chainIds[DeploymentNetwork.Base],
            url: rpcUrls[DeploymentNetwork.Base],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Base}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Fusion]: {
            chainId: chainIds[DeploymentNetwork.Fusion],
            url: rpcUrls[DeploymentNetwork.Fusion],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Fusion}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Mode]: {
            chainId: chainIds[DeploymentNetwork.Mode],
            url: rpcUrls[DeploymentNetwork.Mode],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Mode}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Arbitrum]: {
            chainId: chainIds[DeploymentNetwork.Arbitrum],
            url: rpcUrls[DeploymentNetwork.Arbitrum],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Arbitrum}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Celo]: {
            chainId: chainIds[DeploymentNetwork.Celo],
            url: rpcUrls[DeploymentNetwork.Celo],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Celo}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Avalanche]: {
            chainId: chainIds[DeploymentNetwork.Avalanche],
            url: rpcUrls[DeploymentNetwork.Avalanche],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Avalanche}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Linea]: {
            chainId: chainIds[DeploymentNetwork.Linea],
            url: rpcUrls[DeploymentNetwork.Linea],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Linea}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Scroll]: {
            chainId: chainIds[DeploymentNetwork.Scroll],
            url: rpcUrls[DeploymentNetwork.Scroll],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Scroll}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Aurora]: {
            chainId: chainIds[DeploymentNetwork.Aurora],
            url: rpcUrls[DeploymentNetwork.Aurora],
            gasPrice,
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Aurora}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
                }
            }
        },
        [DeploymentNetwork.Sepolia]: {
            chainId: chainIds[DeploymentNetwork.Sepolia],
            url: rpcUrls[DeploymentNetwork.Sepolia],
            saveDeployments: true,
            live: true,
            deploy: [`deploy/scripts/${DeploymentNetwork.Sepolia}`],
            verify: {
                etherscan: {
                    apiKey: VERIFY_API_KEY
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

    paths: {
        deploy: ['deploy/scripts']
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
