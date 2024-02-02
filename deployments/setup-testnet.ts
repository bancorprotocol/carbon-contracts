import Contracts from '../components/Contracts';
import { getNamedSigners, isTenderly, isTenderlyTestnet, runPendingDeployments } from '../utils/Deploy';
import Logger from '../utils/Logger';
import { NATIVE_TOKEN_ADDRESS, ZERO_ADDRESS } from '../utils/Constants';
import { toWei } from '../utils/Types';
import '@nomiclabs/hardhat-ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
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
    whale: SignerWithAddress;
}

const fundAccount = async (account: string, fundingRequests: FundingRequest[]) => {
    Logger.log(`Funding ${account}...`);

    for (const fundingRequest of fundingRequests) {
        try {
            // for tokens which are missing on a network skip funding request (BNT is not on Base, Arbitrum, etc.)
            if (fundingRequest.token === ZERO_ADDRESS) {
                continue;
            }
            if (fundingRequest.token === NATIVE_TOKEN_ADDRESS) {
                await fundingRequest.whale.sendTransaction({
                    value: fundingRequest.amount,
                    to: account
                });

                continue;
            }

            const tokenContract = await Contracts.ERC20.attach(fundingRequest.token);
            await tokenContract.connect(fundingRequest.whale).transfer(account, fundingRequest.amount);
        } catch (error) {
            Logger.error(`Failed to fund ${account} with ${fundingRequest.amount} of token ${fundingRequest.tokenName}`);
            Logger.error(error);
            Logger.error();
        }
    }
};

const fundAccounts = async () => {
    Logger.log('Funding test accounts...');
    Logger.log();

    const { dai, link, usdc, wbtc, bnt } = await getNamedAccounts();
    const { ethWhale, bntWhale, daiWhale, linkWhale, usdcWhale, wbtcWhale } = await getNamedSigners();

    const fundingRequests = [
        {
            token: NATIVE_TOKEN_ADDRESS,
            tokenName: 'eth',
            amount: toWei(1000),
            whale: ethWhale
        },
        {
            token: bnt,
            tokenName: 'bnt',
            amount: toWei(10_000),
            whale: bntWhale
        },
        {
            token: dai,
            tokenName: 'dai',
            amount: toWei(20_000),
            whale: daiWhale
        },
        {
            token: link,
            tokenName: 'link',
            amount: toWei(10_000),
            whale: linkWhale
        },
        {
            token: usdc,
            tokenName: 'usdc',
            amount: toWei(100_000, 6),
            whale: usdcWhale
        },
        {
            token: wbtc,
            tokenName: 'wbtc',
            amount: toWei(100, 8),
            whale: wbtcWhale
        }
    ];

    const devAddresses = DEV_ADDRESSES.split(',');

    for(const fundingRequest of fundingRequests) {
        if(fundingRequest.token == ZERO_ADDRESS) {
            Logger.log(`Skipping funding for ${fundingRequest.tokenName}`);
        }
        const { whale } = fundingRequest;
        if (!whale) {
            continue;
        }
        const whaleBalance = await whale.getBalance();
        // transfer ETH to the funding account if it doesn't have ETH
        if (whaleBalance.lt(toWei(1))) {
            await fundingRequests[0].whale.sendTransaction({
                value: toWei(1),
                to: whale.address
            });
        }
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

    const srcDir = path.resolve(path.join(__dirname, './tenderly-testnet'));
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
