import { ContractBuilder } from '../../components/ContractBuilder';
import Contracts, { ProxyAdmin, TestERC20Burnable, TestERC20Token, Voucher } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../utils/TokenData';
import { Addressable, toWei } from '../../utils/Types';
import { toAddress } from './Utils';
import { BaseContract, BigNumberish, BytesLike, ContractFactory } from 'ethers';
import { waffle } from 'hardhat';

type CtorArgs = Parameters<any>;
type InitArgs = Parameters<any>;

interface ProxyArguments {
    skipInitialization?: boolean;
    initArgs?: InitArgs;
    ctorArgs?: CtorArgs;
}
export interface Tokens {
    [symbol: string]: TestERC20Burnable;
}

let admin: ProxyAdmin;

export type TokenWithAddress = TestERC20Token | Addressable;

export const proxyAdmin = async () => {
    if (!admin) {
        admin = await Contracts.ProxyAdmin.deploy();
    }

    return admin;
};

const createLogic = async <F extends ContractFactory>(factory: ContractBuilder<F>, ctorArgs: CtorArgs = []) => {
    // eslint-disable-next-line @typescript-eslint/ban-types
    return (factory.deploy as Function)(...(ctorArgs ?? []));
};

const createTransparentProxy = async (
    logicContract: BaseContract,
    skipInitialization = false,
    initArgs: InitArgs = []
) => {
    const admin = await proxyAdmin();
    const data = skipInitialization ? [] : logicContract.interface.encodeFunctionData('initialize', initArgs);
    return Contracts.OptimizedTransparentUpgradeableProxy.deploy(logicContract.address, admin.address, data);
};

export const createProxy = async <F extends ContractFactory>(factory: ContractBuilder<F>, args?: ProxyArguments) => {
    const logicContract = await createLogic(factory, args?.ctorArgs);
    const proxy = await createTransparentProxy(logicContract, args?.skipInitialization, args?.initArgs);

    return factory.attach(proxy.address);
};

interface ProxyUpgradeArgs extends ProxyArguments {
    upgradeCallData?: BytesLike;
}

export const upgradeProxy = async <F extends ContractFactory>(
    proxy: BaseContract,
    factory: ContractBuilder<F>,
    args?: ProxyUpgradeArgs
) => {
    const logicContract = await createLogic(factory, args?.ctorArgs);
    const admin = await proxyAdmin();

    await admin.upgradeAndCall(
        proxy.address,
        logicContract.address,
        logicContract.interface.encodeFunctionData('postUpgrade', [args?.upgradeCallData ?? []])
    );

    return factory.attach(proxy.address);
};

export const createCarbonController = async (voucher: string | Voucher) => {
    const carbonController = await createProxy(Contracts.CarbonController, {
        skipInitialization: false,
        ctorArgs: [toAddress(voucher), ZERO_ADDRESS]
    });

    const upgradedCarbonController = await upgradeProxy(carbonController, Contracts.CarbonController, {
        skipInitialization: false,
        ctorArgs: [toAddress(voucher), carbonController.address]
    });

    return upgradedCarbonController;
};

const createSystemFixture = async () => {
    const voucher = await Contracts.Voucher.deploy(true, 'ipfs://xxx', '');

    const carbonController = await createCarbonController(voucher);

    await voucher.setCarbonController(carbonController.address);

    return {
        carbonController,
        voucher
    };
};

export const createSystem = async () => waffle.loadFixture(createSystemFixture);

export const createToken = async (
    tokenData: TokenData,
    totalSupply: BigNumberish = toWei(1_000_000_000_000),
    burnable = false
): Promise<TokenWithAddress> => {
    const symbol = tokenData.symbol();

    switch (symbol) {
        case TokenSymbol.ETH:
            return { address: NATIVE_TOKEN_ADDRESS };

        case TokenSymbol.USDC:
        case TokenSymbol.TKN:
        case TokenSymbol.TKN0:
        case TokenSymbol.TKN1:
        case TokenSymbol.TKN2: {
            const token = await (burnable ? Contracts.TestERC20Burnable : Contracts.TestERC20Token).deploy(
                tokenData.name(),
                tokenData.symbol(),
                totalSupply
            );

            if (!tokenData.isDefaultDecimals()) {
                await token.updateDecimals(tokenData.decimals());
            }

            return token;
        }

        default:
            throw new Error(`Unsupported type ${symbol}`);
    }
};

export const createBurnableToken = async (tokenData: TokenData, totalSupply: BigNumberish = toWei(1_000_000_000)) =>
    createToken(tokenData, totalSupply, true) as Promise<TestERC20Burnable>;

export const createTestToken = async (totalSupply: BigNumberish = toWei(1_000_000_000)) =>
    createToken(new TokenData(TokenSymbol.TKN), totalSupply) as Promise<TestERC20Burnable>;
