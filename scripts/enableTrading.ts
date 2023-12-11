import Contracts from '../components/Contracts';
import { DeployedContracts, execute, getNamedSigners, InstanceName } from '../utils/Deploy';
import Logger from '../utils/Logger';
import { DEFAULT_DECIMALS, NATIVE_TOKEN_ADDRESS, TokenSymbol } from '../utils/TokenData';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import { CoinGeckoClient } from 'coingecko-api-v3';
import Decimal from 'decimal.js';
import fs from 'fs';

interface EnvOptions {
    ENABLE_TRADING?: boolean;
}

const { ENABLE_TRADING: enableTrading }: EnvOptions = process.env as any as EnvOptions;

interface TokenData {
    address: string;
    ethVirtualBalance: Decimal;
    tokenVirtualBalance: Decimal;
}

const MAX_PRECISION = 16;
const TOKEN_ADDRESSES: string[] = [];

interface TokenOverride {
    address: string;
    symbol?: string;
    decimals?: number;
}

const TOKEN_OVERRIDES: TokenOverride[] = [
    {
        address: '0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2',
        symbol: 'MKR'
    },
    {
        address: '0x50d1c9771902476076ecfc8b2a83ad6b9355a4c9',
        symbol: 'FTT'
    }
];

const main = async () => {
    const { deployer } = await getNamedSigners();
    const carbonPOL = await DeployedContracts.CarbonPOL.deployed();

    const client = new CoinGeckoClient({
        timeout: 10000,
        autoRetry: true
    });

    /* eslint-disable camelcase */
    const tokenPrices = {
        ...(await client.simpleTokenPrice({
            id: 'ethereum',
            contract_addresses: [...TOKEN_ADDRESSES].join(','),
            vs_currencies: 'USD'
        }))
    };
    /* eslint-enable camelcase */

    const ethPriceRes = await client.simplePrice({
        ids: 'ethereum',
        vs_currencies: 'USD'
    });

    const ethPrice = new Decimal(ethPriceRes.ethereum.usd);

    Logger.log();
    Logger.log('Looking for disabled tokens...');

    const unknownTokens: Record<string, string> = {};

    const tokens: Record<string, TokenData> = {};

    let symbol: string;
    let decimals: number;
    for (let i = 0; i < TOKEN_ADDRESSES.length; i++) {
        const token = TOKEN_ADDRESSES[i];

        if (token === NATIVE_TOKEN_ADDRESS) {
            symbol = TokenSymbol.ETH;
            decimals = DEFAULT_DECIMALS;
        } else {
            const tokenOverride = TOKEN_OVERRIDES.find((t) => t.address.toLowerCase() === token.toLowerCase());
            const tokenContract = await Contracts.ERC20.attach(token, deployer);
            symbol = tokenOverride?.symbol ?? (await tokenContract.symbol());
            decimals = tokenOverride?.decimals ?? (await tokenContract.decimals());
        }

        Logger.log();
        Logger.log(`Checking ${symbol} status [${token}]...`);

        if (await carbonPOL.tradingEnabled(token)) {
            Logger.error('  Skipping already enabled token...');
            continue;
        }

        const tokenPriceData = tokenPrices[token.toLowerCase()];
        if (!tokenPriceData) {
            unknownTokens[symbol] = token;

            Logger.error('  Skipping unknown token');
            continue;
        }
        const tokenPrice = new Decimal(tokenPriceData.usd);
        const rate = ethPrice.div(tokenPrice);

        Logger.log(`  ${TokenSymbol.ETH} price: $${ethPrice.toFixed()}`);
        Logger.log(`  ${symbol} price: $${tokenPrice.toFixed()}`);
        Logger.log(`  ${symbol} to ${TokenSymbol.ETH} rate: ${rate.toFixed(MAX_PRECISION)}`);

        const tokenPriceNormalizationFactor = new Decimal(10).pow(DEFAULT_DECIMALS - decimals);

        if (decimals !== DEFAULT_DECIMALS) {
            Logger.log(`  ${symbol} decimals: ${decimals}`);
            Logger.log(
                `  ${symbol} to ${TokenSymbol.ETH} rate normalized: ${rate
                    .div(tokenPriceNormalizationFactor)
                    .toFixed(MAX_PRECISION)}`
            );
        }

        const decimalsFactor = new Decimal(10).pow(decimals);

        Logger.log(`  Found pending token ${symbol} [${token}]...`);

        const normalizedTokenPrice = tokenPrice.div(decimalsFactor);
        const normalizedETHPrice = ethPrice.div(new Decimal(10).pow(DEFAULT_DECIMALS));

        const maxDecimals = Math.max(normalizedETHPrice.decimalPlaces(), normalizedTokenPrice.decimalPlaces());
        const maxDecimalsFactor = new Decimal(10).pow(maxDecimals);
        const buffer = new Decimal(10).pow(6); // buffer for increasing precision
        const ethVirtualBalance = normalizedTokenPrice.mul(maxDecimalsFactor).mul(buffer);
        const tokenVirtualBalance = normalizedETHPrice.mul(maxDecimalsFactor).mul(buffer);

        Logger.log(`  Suggested ${TokenSymbol.ETH} virtual balance: ${ethVirtualBalance.toFixed()}`);
        Logger.log(`  Suggested ${symbol} virtual balance: ${tokenVirtualBalance.toFixed()}`);

        if (enableTrading) {
            await execute({
                name: InstanceName.CarbonPOL,
                methodName: 'enableTrading',
                args: [
                    token,
                    {
                        ethAmount: ethVirtualBalance.toFixed().toString(),
                        tokenAmount: tokenVirtualBalance.toFixed().toString()
                    }
                ],
                from: deployer.address
            });
        }

        tokens[symbol] = {
            address: token,
            ethVirtualBalance,
            tokenVirtualBalance
        };
    }

    Logger.log('');
    Logger.log('********************************************************************************');
    Logger.log('');

    const entries = Object.entries(tokens);
    if (entries.length === 0) {
        Logger.log('Did not find any pending tokens...');
        Logger.log();

        return;
    }

    Logger.log(`Found ${entries.length} pending tokens:`);
    Logger.log();

    for (const [symbol, poolData] of entries) {
        Logger.log(`${symbol}:`);
        Logger.log(`  Token: ${poolData.address}`);
        Logger.log(`  Suggested ${TokenSymbol.ETH} virtual balance: ${poolData.ethVirtualBalance.toFixed()}`);
        Logger.log(`  Suggested ${symbol} virtual balance: ${poolData.tokenVirtualBalance.toFixed()}`);
        Logger.log('');
    }

    Logger.log('********************************************************************************');
    Logger.log('');

    if (Object.keys(unknownTokens).length !== 0) {
        Logger.log('Unknown tokens:');

        for (const [symbol, address] of Object.entries(unknownTokens)) {
            Logger.log(`${symbol} - ${address}`);
        }

        Logger.log('');
    }
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        Logger.error(error);
        process.exit(1);
    });
