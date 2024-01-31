import { DeploymentNetwork, ZERO_ADDRESS } from '../utils/Constants';
import chainIds from '../utils/chainIds.json';

interface EnvOptions {
    TENDERLY_NETWORK_NAME?: string;
}

const { TENDERLY_NETWORK_NAME = 'mainnet' }: EnvOptions = process.env as any as EnvOptions;

const TENDERLY_NETWORK_ID = chainIds[TENDERLY_NETWORK_NAME as keyof typeof chainIds];

const mainnet = (address: string) => {
    if (TENDERLY_NETWORK_ID === chainIds['mainnet']) {
        return {
            [DeploymentNetwork.Mainnet]: address,
            [DeploymentNetwork.Tenderly]: address,
            [DeploymentNetwork.TenderlyTestnet]: address
        };
    }
    return {
        [DeploymentNetwork.Mainnet]: address
    };
};

const base = (address: string) => {
    if (TENDERLY_NETWORK_ID === chainIds['base']) {
        return {
            [DeploymentNetwork.Base]: address,
            [DeploymentNetwork.Tenderly]: address,
            [DeploymentNetwork.TenderlyTestnet]: address
        };
    }
    return {
        [DeploymentNetwork.Base]: address
    };
};

const arbitrum = (address: string) => {
    if (TENDERLY_NETWORK_ID === chainIds['arbitrum']) {
        return {
            [DeploymentNetwork.Arbitrum]: address,
            [DeploymentNetwork.Tenderly]: address,
            [DeploymentNetwork.TenderlyTestnet]: address
        };
    }
    return {
        [DeploymentNetwork.Arbitrum]: address
    };
};

const sepolia = (address: string) => {
    if (TENDERLY_NETWORK_ID === chainIds['sepolia']) {
        return {
            [DeploymentNetwork.Sepolia]: address,
            [DeploymentNetwork.Tenderly]: address,
            [DeploymentNetwork.TenderlyTestnet]: address
        };
    }
    return {
        [DeploymentNetwork.Sepolia]: address
    };
};

const mantle = (address: string) => {
    if (TENDERLY_NETWORK_ID === chainIds['mantle']) {
        return {
            [DeploymentNetwork.Mantle]: address,
            [DeploymentNetwork.Tenderly]: address,
            [DeploymentNetwork.TenderlyTestnet]: address
        };
    }
    return {
        [DeploymentNetwork.Mantle]: address
    };
};

const TestNamedAccounts = {
    ethWhale: {
        ...mainnet('0xDA9dfA130Df4dE4673b89022EE50ff26f6EA73Cf'),
        ...base('0xF977814e90dA44bFA03b6295A0616a897441aceC'),
        ...arbitrum('0xF977814e90dA44bFA03b6295A0616a897441aceC'),
        ...mantle('0xf89d7b9c864f589bbF53a82105107622B35EaA40')
    },
    daiWhale: {
        ...mainnet('0x1B7BAa734C00298b9429b518D621753Bb0f6efF2'),
        ...base('0xe9b14a1Be94E70900EDdF1E22A4cB8c56aC9e10a'),
        ...arbitrum('0xd85E038593d7A098614721EaE955EC2022B9B91B'),
        ...mantle(ZERO_ADDRESS)
    },
    usdcWhale: {
        ...mainnet('0x55FE002aefF02F77364de339a1292923A15844B8'),
        ...mantle('0x7427b4Fd78974Ba1C3B5d69e2F1B8ACF654fEB44'),
        ...base('0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A'),
        ...arbitrum('0xd85E038593d7A098614721EaE955EC2022B9B91B')
    },
    wbtcWhale: {
        ...mainnet('0x051d091B254EcdBBB4eB8E6311b7939829380b27'),
        ...arbitrum('0x489ee077994B6658eAfA855C308275EAd8097C4A'),
        ...mantle('0xa6b12425F236EE85c6E0E60df9c422C9e603cf80')
    },
    bntWhale: {
        ...mainnet('0x221A0e3C9AcEa6B3f1CC9DfC7063509c89bE7BC3'),
        ...mantle(ZERO_ADDRESS)
    },
    linkWhale: {
        ...mainnet('0xc6bed363b30DF7F35b601a5547fE56cd31Ec63DA'),
        ...arbitrum('0x191c10Aa4AF7C30e871E70C95dB0E4eb77237530'),
        ...mantle(ZERO_ADDRESS)
    },
};

const TokenNamedAccounts = {
    dai: {
        ...mainnet('0x6B175474E89094C44Da98b954EedeAC495271d0F'),
        ...base('0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb'),
        ...arbitrum('0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1'),
        ...mantle(ZERO_ADDRESS)
    },
    weth: {
        ...mainnet('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'),
        ...base('0x4200000000000000000000000000000000000006'),
        ...arbitrum('0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'),
        ...mantle('0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111')
    },
    usdc: {
        ...mainnet('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'),
        ...base('0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'),
        ...arbitrum('0xaf88d065e77c8cC2239327C5EDb3A432268e5831'),
        ...mantle('0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9')
    },
    wbtc: {
        ...mainnet('0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'),
        ...base(ZERO_ADDRESS),
        ...arbitrum('0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f'),
        ...mantle('0xCAbAE6f6Ea1ecaB08Ad02fE02ce9A44F09aebfA2')
    },
    bnt: {
        ...mainnet('0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C'),
        ...base(ZERO_ADDRESS),
        ...arbitrum(ZERO_ADDRESS),
        ...mantle(ZERO_ADDRESS)
    },
    link: {
        ...mainnet('0x514910771AF9Ca656af840dff83E8264EcF986CA'),
        ...base(ZERO_ADDRESS),
        ...arbitrum(ZERO_ADDRESS),
        ...mantle(ZERO_ADDRESS)
    },
};

const BancorNamedAccounts = {
    bancorNetworkV3: { 
        ...mainnet('0xeEF417e1D5CC832e619ae18D2F140De2999dD4fB'),
        ...mantle(ZERO_ADDRESS),
        ...base(ZERO_ADDRESS),
        ...arbitrum(ZERO_ADDRESS)
    }
};

export const NamedAccounts = {
    deployer: {
        ...mainnet('ledger://0x5bEBA4D3533a963Dedb270a95ae5f7752fA0Fe22'),
        ...sepolia('ledger://0x0f28D58c00F9373C00811E9576eE803B4eF98abe'),
        ...base('ledger://0x0f28D58c00F9373C00811E9576eE803B4eF98abe'),
        ...arbitrum('ledger://0x0f28D58c00F9373C00811E9576eE803B4eF98abe'),
        ...mantle('ledger://0x5bEBA4D3533a963Dedb270a95ae5f7752fA0Fe22'),
    },
    deployerV2: { ...mainnet('0xdfeE8DC240c6CadC2c7f7f9c257c259914dEa84E') },
    foundationMultisig: { ...mainnet('0xeBeD45Ca22fcF70AdCcAb7618C51A3Dbb06C8d83') },
    foundationMultisig2: { ...mainnet('0x0c333d48Af19c2b42577f3C8f4779F0347F8C819') },
    daoMultisig: { ...mainnet('0x7e3692a6d8c34a762079fa9057aed87be7e67cb8') },
    daoPauserMultisig: { ...mainnet('0xc140c1CD2e587fC04DAa780d49b616F768476660') },

    ...TokenNamedAccounts,
    ...TestNamedAccounts,
    ...BancorNamedAccounts
};
