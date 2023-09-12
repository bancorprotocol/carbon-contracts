import Contracts from '../components/Contracts';
import { DeployedContracts, execute, getNamedSigners, InstanceName } from '../utils/Deploy';
import Logger from '../utils/Logger';
import { DEFAULT_DECIMALS, TokenSymbol } from '../utils/TokenData';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import { CoinGeckoClient } from 'coingecko-api-v3';
import Decimal from 'decimal.js';

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

const main = async () => {
    const { deployer } = await getNamedSigners();
    const carbonPOL = await DeployedContracts.CarbonPOL.deployed();

    const tokenAddressesEnv = process.env.TOKEN_ADDRESSES;
    if (!tokenAddressesEnv) {
        console.error(`no tokens passed in - pass in token addresses like so: TOKEN_ADDRESSES='0x...','0x...'`);
        return;
    }

    // Remove single quotes and whitespace, then split by commas
    const allTokens = tokenAddressesEnv
        .replace(/'/g, '')
        .split(',')
        .map((address) => address.trim());

    const client = new CoinGeckoClient({
        timeout: 10000,
        autoRetry: true
    });

    /* eslint-disable camelcase */
    const tokenPrices = {
        ...(await client.simpleTokenPrice({
            id: 'ethereum',
            contract_addresses: [...allTokens].join(','),
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
    for (let i = 0; i < allTokens.length; i++) {
        const token = allTokens[i];

        const tokenContract = await Contracts.ERC20.attach(token, deployer);
        symbol = await tokenContract.symbol();
        decimals = await tokenContract.decimals();

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
        const ethVirtualBalance = normalizedETHPrice.mul(maxDecimalsFactor);
        const tokenVirtualBalance = normalizedTokenPrice.mul(maxDecimalsFactor);

        Logger.log(`  Suggested ${TokenSymbol.ETH} virtual balance: ${ethVirtualBalance.toFixed()}`);
        Logger.log(`  Suggested ${symbol} virtual balance: ${tokenVirtualBalance.toFixed()}`);

        if (enableTrading) {
            await execute({
                name: InstanceName.CarbonPOL,
                methodName: 'enableTrading',
                args: [token, { ethAmount: ethVirtualBalance.toString(), tokenAmount: tokenVirtualBalance.toString() }],
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
