import { isTenderly, runPendingDeployments } from '../utils/Deploy';
import Logger from '../utils/Logger';
import { NATIVE_TOKEN_ADDRESS, ZERO_ADDRESS } from '../utils/Constants';
import { toWei } from '../utils/Types';
import { setTokenBalance } from '../test/helpers/Utils';
import '@nomiclabs/hardhat-ethers';
import '@tenderly/hardhat-tenderly';
import '@typechain/hardhat';
import AdmZip from 'adm-zip';
import { BigNumber } from 'ethers';
import { getNamedAccounts } from 'hardhat';
import 'hardhat-deploy';
import { capitalize } from 'lodash';
import path from 'path';

interface EnvOptions {
    DEV_ADDRESSES: string;
    TESTNET_NAME: string;
    TENDERLY_PROJECT: string;
    TENDERLY_USERNAME: string;
    TENDERLY_TESTNET_ID: string;
    TENDERLY_NETWORK_NAME: string;
    TENDERLY_TESTNET_PROVIDER_URL?: string;
}

const {
    DEV_ADDRESSES,
    TESTNET_NAME,
    TENDERLY_PROJECT,
    TENDERLY_USERNAME,
    TENDERLY_TESTNET_ID: testnetId = '',
    TENDERLY_NETWORK_NAME = 'mainnet',
    TENDERLY_TESTNET_PROVIDER_URL: testnetRpcUrl
}: EnvOptions = process.env as any as EnvOptions;

interface FundingRequest {
    token: string;
    tokenName: string;
    amount: BigNumber;
}

const fundAccount = async (account: string, fundingRequests: FundingRequest[]) => {
    Logger.log(`Funding ${account}...`);

    for (const fundingRequest of fundingRequests) {
        // for tokens which are missing on a network skip funding request (BNT is not on Base, Arbitrum, etc.)
        if (fundingRequest.token === ZERO_ADDRESS) {
            continue;
        }

        // set the balance directly on the tenderly testnet instead of transferring from a whale
        await setTokenBalance({ address: fundingRequest.token }, account, fundingRequest.amount);
    }
};

const fundAccounts = async () => {
    Logger.log('Funding test accounts...');
    Logger.log();

    const { dai, link, usdc, wbtc, bnt } = await getNamedAccounts();

    const fundingRequests: FundingRequest[] = [
        {
            token: NATIVE_TOKEN_ADDRESS,
            tokenName: 'eth',
            amount: toWei(1000)
        },
        {
            token: bnt,
            tokenName: 'bnt',
            amount: toWei(10_000)
        },
        {
            token: dai,
            tokenName: 'dai',
            amount: toWei(20_000)
        },
        {
            token: link,
            tokenName: 'link',
            amount: toWei(10_000)
        },
        {
            token: usdc,
            tokenName: 'usdc',
            amount: toWei(100_000, 6)
        },
        {
            token: wbtc,
            tokenName: 'wbtc',
            amount: toWei(100, 8)
        }
    ];

    if (DEV_ADDRESSES == undefined) {
        Logger.log('no dev addresses provided');
        return;
    }
    const devAddresses = DEV_ADDRESSES.split(',');

    if (devAddresses.length == 0) {
        Logger.log('no dev addresses provided');
        return;
    }

    for (const account of devAddresses) {
        await fundAccount(account, fundingRequests);
    }

    Logger.log();
};

const runDeployments = async () => {
    Logger.log('Running pending deployments...');
    Logger.log();

    await runPendingDeployments();

    Logger.log();
};

const archiveArtifacts = async () => {
    const zip = new AdmZip();

    const srcDir = path.resolve(path.join(__dirname, './tenderly'));
    const dest = path.resolve(path.join(__dirname, '..', 'testnets', `testnet-${testnetId}.zip`));

    zip.addLocalFolder(srcDir);
    zip.writeZip(dest);

    Logger.log(`Archived ${srcDir} to ${dest}...`);
    Logger.log();
};

const main = async () => {
    if (!isTenderly()) {
        throw new Error('Invalid network');
    }

    Logger.log();

    await runDeployments();

    await fundAccounts();

    await archiveArtifacts();

    const networkName = capitalize(TENDERLY_NETWORK_NAME);

    const description = `${networkName} ${TESTNET_NAME ? TESTNET_NAME : ""} Tenderly Testnet`;

    Logger.log('********************************************************************************');
    Logger.log();
    Logger.log(description);
    Logger.log('‾'.repeat(description.length));
    Logger.log(`   RPC: ${testnetRpcUrl}`);
    Logger.log(`   Dashboard: https://dashboard.tenderly.co/${TENDERLY_USERNAME}/${TENDERLY_PROJECT}/testnet/${testnetId}`);
    Logger.log();
    Logger.log('********************************************************************************');
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        Logger.error(error);
        process.exit(1);
    });
