import { ArtifactData } from '../components/ContractBuilder';
import { CarbonController, FeeBurner, IVersioned, ProxyAdmin, Voucher } from '../components/Contracts';
import Logger from '../utils/Logger';
import { DeploymentNetwork, ZERO_BYTES } from './Constants';
import { RoleIds } from './Roles';
import { toWei } from './Types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, Contract, ContractInterface, ContractTransaction, utils } from 'ethers';
import fs from 'fs';
import glob from 'glob';
import { config, deployments, ethers, getNamedAccounts, tenderly } from 'hardhat';
import {
    Address,
    DeployFunction,
    Deployment as DeploymentData,
    ProxyOptions as DeployProxyOptions
} from 'hardhat-deploy/types';
import path from 'path';

const {
    deploy: deployContract,
    execute: executeTransaction,
    getNetworkName,
    save: saveContract,
    getExtendedArtifact,
    getArtifact,
    run
} = deployments;

const { AbiCoder } = utils;

const tenderlyNetwork = tenderly.network();

interface EnvOptions {
    TEST_FORK?: boolean;
}

const { TEST_FORK: isTestFork }: EnvOptions = process.env as any as EnvOptions;

enum NewInstanceName {
    CarbonController = 'CarbonController',
    ProxyAdmin = 'ProxyAdmin',
    Voucher = 'Voucher',
    FeeBurner = 'FeeBurner'
}

export const LegacyInstanceName = {};

export const InstanceName = {
    ...LegacyInstanceName,
    ...NewInstanceName
};

export type InstanceName = NewInstanceName;

const deployed = <F extends Contract>(name: InstanceName) => ({
    deployed: async () => ethers.getContract<F>(name)
});

const DeployedNewContracts = {
    CarbonController: deployed<CarbonController>(InstanceName.CarbonController),
    ProxyAdmin: deployed<ProxyAdmin>(InstanceName.ProxyAdmin),
    Voucher: deployed<Voucher>(InstanceName.Voucher),
    FeeBurner: deployed<FeeBurner>(InstanceName.FeeBurner)
};

export const DeployedContracts = {
    ...DeployedNewContracts
};

export const isTenderlyFork = () => getNetworkName() === DeploymentNetwork.Tenderly;
export const isMainnetFork = () => isTenderlyFork();
export const isMainnet = () => getNetworkName() === DeploymentNetwork.Mainnet || isMainnetFork();
export const isRinkeby = () => getNetworkName() === DeploymentNetwork.Rinkeby;
export const isLive = () => (isMainnet() && !isMainnetFork()) || isRinkeby();

const TEST_MINIMUM_BALANCE = toWei(10);
const TEST_FUNDING = toWei(10);

export const getNamedSigners = async (): Promise<Record<string, SignerWithAddress>> => {
    const signers: Record<string, SignerWithAddress> = {};

    for (const [name, address] of Object.entries(await getNamedAccounts())) {
        signers[name] = await ethers.getSigner(address);
    }

    return signers;
};

export const fundAccount = async (account: string | SignerWithAddress) => {
    if (!isMainnetFork()) {
        return;
    }

    const address = typeof account === 'string' ? account : account.address;

    const balance = await ethers.provider.getBalance(address);
    if (balance.gte(TEST_MINIMUM_BALANCE)) {
        return;
    }

    const { ethWhale } = await getNamedSigners();

    return ethWhale.sendTransaction({
        value: TEST_FUNDING,
        to: address
    });
};

interface SaveTypeOptions {
    name: InstanceName;
    contract: string;
}

const saveTypes = async (options: SaveTypeOptions) => {
    const { name, contract } = options;

    // don't attempt to save the types for legacy contracts
    if (Object.keys(LegacyInstanceName).includes(name)) {
        return;
    }

    const { sourceName } = await getArtifact(contract);
    const contractSrcDir = path.dirname(sourceName);

    const typechainDir = path.resolve('./', config.typechain.outDir);

    // for some reason, the types of some contracts are stored in a "Contract.sol" dir, in which case we'd have to use
    // it as the root source dir
    let srcDir;
    let factoriesSrcDir;
    if (fs.existsSync(path.join(typechainDir, sourceName))) {
        srcDir = path.join(typechainDir, sourceName);
        factoriesSrcDir = path.join(typechainDir, 'factories', sourceName);
    } else {
        srcDir = path.join(typechainDir, contractSrcDir);
        factoriesSrcDir = path.join(typechainDir, 'factories', contractSrcDir);
    }

    const typesDir = path.join(config.paths.deployments, getNetworkName(), 'types');
    const destDir = path.join(typesDir, contractSrcDir);
    const factoriesDestDir = path.join(typesDir, 'factories', contractSrcDir);

    if (!fs.existsSync(destDir)) {
        fs.mkdirSync(destDir, { recursive: true });
    }

    if (!fs.existsSync(factoriesDestDir)) {
        fs.mkdirSync(factoriesDestDir, { recursive: true });
    }

    // save the factory typechain
    fs.copyFileSync(
        path.join(factoriesSrcDir, `${contract}__factory.ts`),
        path.join(factoriesDestDir, `${name}__factory.ts`)
    );

    // save the typechain of the contract itself
    fs.copyFileSync(path.join(srcDir, `${contract}.ts`), path.join(destDir, `${name}.ts`));
};

interface ProxyOptions {
    skipInitialization?: boolean;
    args?: any[];
    initImpl?: boolean;
    initImplArgs?: any[];
}

interface BaseDeployOptions {
    name: InstanceName;
    contract?: string;
    args?: any[];
    from: string;
    value?: BigNumber;
    contractArtifactData?: ArtifactData;
    legacy?: boolean;
}

interface DeployOptions extends BaseDeployOptions {
    proxy?: ProxyOptions;
}

const PROXY_CONTRACT = 'OptimizedTransparentProxy';
const INITIALIZE = 'initialize';
const POST_UPGRADE = 'postUpgrade';

const WAIT_CONFIRMATIONS = isLive() ? 2 : 1;

interface FunctionParams {
    name?: string;
    contractName?: string;
    contractArtifactData?: ArtifactData;
    methodName?: string;
    args?: any[];
}

const logParams = async (params: FunctionParams) => {
    const { name, contractName, contractArtifactData, methodName, args = [] } = params;

    if (!name && !contractArtifactData && !contractName) {
        throw new Error('Either name, contractArtifactData, or contractName must be provided!');
    }

    let contractInterface: ContractInterface;

    if (name) {
        ({ interface: contractInterface } = await ethers.getContract(name));
    } else if (contractArtifactData) {
        contractInterface = new utils.Interface(contractArtifactData!.abi);
    } else {
        ({ interface: contractInterface } = await ethers.getContractFactory(contractName!));
    }

    const fragment = methodName ? contractInterface.getFunction(methodName) : contractInterface.deploy;

    Logger.log(`  ${methodName ?? 'constructor'} params: ${args.length === 0 ? '[]' : ''}`);
    if (args.length === 0) {
        return;
    }

    for (const [i, arg] of args.entries()) {
        const input = fragment.inputs[i];
        Logger.log(`    ${input.name} (${input.type}): ${arg.toString()}`);
    }
};

interface TypedParam {
    name: string;
    type: string;
    value: any;
}

const logTypedParams = async (methodName: string, params: TypedParam[] = []) => {
    Logger.log(`  ${methodName} params: ${params.length === 0 ? '[]' : ''}`);
    if (params.length === 0) {
        return;
    }

    for (const { name, type, value } of params) {
        Logger.log(`    ${name} (${type}): ${value.toString()}`);
    }
};

export const deploy = async (options: DeployOptions) => {
    const { name, contract, from, value, args, contractArtifactData, proxy } = options;
    const isProxy = !!proxy;
    const contractName = contract ?? name;

    await fundAccount(from);

    let proxyOptions: DeployProxyOptions = {};

    const customAlias = contractName === name ? '' : ` as ${name};`;

    if (isProxy) {
        const proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();

        proxyOptions = {
            proxyContract: PROXY_CONTRACT,
            owner: await proxyAdmin.owner(),
            viaAdminContract: InstanceName.ProxyAdmin,
            execute: proxy.skipInitialization
                ? undefined
                : { init: { methodName: INITIALIZE, args: proxy.args ? proxy.args : [] } }
        };

        Logger.log(`  deploying proxy ${contractName}${customAlias}`);
    } else {
        Logger.log(`  deploying ${contractName}${customAlias}`);
    }

    await logParams({ contractName, contractArtifactData, args });

    const res = await deployContract(name, {
        contract: contractArtifactData ?? contractName,
        from,
        value,
        args,
        proxy: isProxy ? proxyOptions : undefined,
        waitConfirmations: WAIT_CONFIRMATIONS,
        log: true
    });

    if (isProxy && proxy.initImpl) {
        if (!res.implementation) {
            throw new Error(`Implementation address for ${contractName} missing`);
        }
        await initializeImplementation({
            name,
            address: res.implementation,
            args: proxy.initImplArgs,
            from
        });
        Logger.log(`  initialized proxy implementation`);
    }

    // if (!proxy) {
    const data = { name, contract: contractName };

    await saveTypes(data);

    await verifyTenderlyFork({
        address: res.address,
        proxy: isProxy,
        implementation: isProxy ? res.implementation : undefined,
        ...data
    });
    // }

    return res.address;
};

export const deployProxy = async (options: DeployOptions, proxy: ProxyOptions = {}) =>
    deploy({
        ...options,
        proxy
    });

// an array of typed parameters which will be encoded and passed to the postUpgrade callback
//
// for example:
//
// postUpgradeArgs: [
//    {
//        name: 'x',
//        type: 'uint256',
//        value: 12
//    },
//    {
//        name: 'y',
//        type: 'string',
//        value: 'Hello World!'
//    }
// ]
interface UpgradeProxyOptions extends DeployOptions {
    postUpgradeArgs?: TypedParam[];
    initImpl?: boolean;
    initImplArgs?: any[];
}

export const upgradeProxy = async (options: UpgradeProxyOptions) => {
    const { name, contract, from, value, args, postUpgradeArgs, initImpl, initImplArgs, contractArtifactData } =
        options;
    const contractName = contract ?? name;

    await fundAccount(from);

    const deployed = await DeployedContracts[name].deployed();
    if (!deployed) {
        throw new Error(`Proxy ${name} can't be found!`);
    }

    const proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
    const prevVersion = await (deployed as IVersioned).version();

    let upgradeCallData;
    if (postUpgradeArgs && postUpgradeArgs.length) {
        const types = postUpgradeArgs.map(({ type }) => type);
        const values = postUpgradeArgs.map(({ value }) => value);
        const abiCoder = new AbiCoder();

        upgradeCallData = [abiCoder.encode(types, values)];
    } else {
        upgradeCallData = [ZERO_BYTES];
    }

    const proxyOptions = {
        proxyContract: PROXY_CONTRACT,
        owner: await proxyAdmin.owner(),
        viaAdminContract: InstanceName.ProxyAdmin,
        execute: { onUpgrade: { methodName: POST_UPGRADE, args: upgradeCallData } }
    };

    Logger.log(`  upgrading proxy ${contractName} V${prevVersion}`);

    await logTypedParams(POST_UPGRADE, postUpgradeArgs);
    await logParams({ contractName, args });

    const res = await deployContract(name, {
        contract: contractArtifactData ?? contractName,
        from,
        value,
        args,
        proxy: proxyOptions,
        waitConfirmations: WAIT_CONFIRMATIONS,
        log: true
    });

    if (initImpl) {
        if (!res.implementation) {
            throw new Error(`Implementation address for ${contractName} missing`);
        }
        await initializeImplementation({
            name,
            address: res.implementation,
            args: initImplArgs,
            from
        });
        Logger.log(`  initialized proxy implementation`);
    }

    const newVersion = await (deployed as IVersioned).version();

    Logger.log(`  upgraded proxy ${contractName} V${prevVersion} to V${newVersion}`);

    await verifyTenderlyFork({
        name,
        contract: contractName,
        address: res.address,
        proxy: true,
        implementation: res.implementation
    });

    return res.address;
};

interface ExecuteOptions {
    name: InstanceName;
    methodName: string;
    args?: any[];
    from: string;
    value?: BigNumber;
}

export const execute = async (options: ExecuteOptions) => {
    const { name, methodName, from, value, args } = options;
    const contract = await ethers.getContract(name);

    Logger.info(`  executing ${name}.${methodName} (${contract.address})`);

    await fundAccount(from);

    await logParams({ name, args, methodName });

    return executeTransaction(
        name,
        { from, value, waitConfirmations: WAIT_CONFIRMATIONS, log: true },
        methodName,
        ...(args ?? [])
    );
};

interface InitializeProxyOptions {
    name: InstanceName;
    proxyName: InstanceName;
    args?: any[];
    from: string;
}

export const initializeProxy = async (options: InitializeProxyOptions) => {
    const { name, proxyName, args, from } = options;

    Logger.log(`  initializing proxy ${name}`);

    await execute({
        name: proxyName,
        methodName: INITIALIZE,
        args,
        from
    });

    const { address } = await ethers.getContract(proxyName);

    await save({
        name,
        address,
        proxy: true,
        skipVerification: true
    });

    return address;
};

interface InitializeImplementationOptions {
    name: InstanceName;
    address: string;
    args?: any[];
    from: string;
}

export const initializeImplementation = async (options: InitializeImplementationOptions) => {
    const { name, address, args, from } = options;
    const signer = await ethers.getSigner(from);

    Logger.log(`  initializing implementation of ${name}`);

    let tx: ContractTransaction;

    await execute({
        name: (name + '_Implementation') as InstanceName,
        methodName: INITIALIZE,
        args: args ? args : [],
        from
    });
};

interface RolesOptions {
    name: InstanceName;
    id: (typeof RoleIds)[number];
    member: string;
    from: string;
}

interface RenounceRoleOptions {
    name: InstanceName;
    id: (typeof RoleIds)[number];
    from: string;
}

const setRole = async (options: RolesOptions, methodName: string) => {
    const { name, id, from, member } = options;

    return execute({
        name,
        methodName,
        args: [id, member],
        from
    });
};

export const grantRole = async (options: RolesOptions) => setRole(options, 'grantRole');
export const revokeRole = async (options: RolesOptions) => setRole(options, 'revokeRole');
export const renounceRole = async (options: RenounceRoleOptions) =>
    setRole({ member: options.from, ...options }, 'renounceRole');

interface Deployment {
    name: InstanceName;
    contract?: string;
    address: Address;
    proxy?: boolean;
    implementation?: Address;
    skipVerification?: boolean;
}

export const save = async (deployment: Deployment) => {
    const { name, contract, address, proxy, skipVerification } = deployment;

    const contractName = contract ?? name;
    const { abi } = await getExtendedArtifact(contractName);

    // save the deployment json data in the deployments folder
    await saveContract(name, { abi, address });

    if (proxy) {
        const { abi } = await getExtendedArtifact(PROXY_CONTRACT);
        await saveContract(`${name}_Proxy`, { abi, address });
    }

    // publish the contract to a Tenderly fork
    if (!skipVerification) {
        await verifyTenderlyFork(deployment);
    }
};

interface ContractData {
    name: string;
    address: Address;
}

const verifyTenderlyFork = async (deployment: Deployment) => {
    // verify contracts on Tenderly only for mainnet or tenderly mainnet forks deployments
    if (!isTenderlyFork() || isTestFork) {
        return;
    }

    const { name, contract, address, proxy, implementation } = deployment;

    const contracts: ContractData[] = [];
    let contractAddress = address;

    if (proxy) {
        contracts.push({
            name: PROXY_CONTRACT,
            address
        });

        contractAddress = implementation!;
    }

    contracts.push({
        name: contract ?? name,
        address: contractAddress
    });

    for (const contract of contracts) {
        Logger.log('  verifying on tenderly', contract.name, 'at', contract.address);

        await tenderlyNetwork.verify(contract);
    }
};

export const deploymentTagExists = (tag: string) => {
    const externalDeployments = config.external?.deployments![getNetworkName()];
    const migrationsPath = path.resolve(
        __dirname,
        '../',
        externalDeployments ? externalDeployments[0] : path.join('deployments', getNetworkName()),
        '.migrations.json'
    );

    if (!fs.existsSync(migrationsPath)) {
        return false;
    }

    const migrations = JSON.parse(fs.readFileSync(migrationsPath, 'utf-8'));
    const tags = Object.keys(migrations).map((tag) => deploymentFileNameToTag(tag));

    return tags.includes(tag);
};

const deploymentFileNameToTag = (filename: string) => Number(path.basename(filename).split('-')[0]).toString();

export const getPreviousDeploymentTag = (tag: string) => {
    const files = fs.readdirSync(config.paths.deploy[0]).sort();

    const index = files.map((f) => deploymentFileNameToTag(f)).lastIndexOf(tag);
    if (index === -1) {
        throw new Error(`Unable to find deployment with tag ${tag}`);
    }

    return index === 0 ? undefined : deploymentFileNameToTag(files[index - 1]);
};

export const getLatestDeploymentTag = () => {
    const files = fs.readdirSync(config.paths.deploy[0]).sort();

    return Number(files[files.length - 1].split('-')[0]).toString();
};

export const deploymentMetadata = (filename: string) => {
    const id = path.basename(filename).split('.')[0];
    const tag = deploymentFileNameToTag(filename);
    const prevTag = getPreviousDeploymentTag(tag);

    return {
        id,
        tag,
        dependency: prevTag
    };
};

export const setDeploymentMetadata = (filename: string, func: DeployFunction) => {
    const { id, tag, dependency } = deploymentMetadata(filename);

    func.id = id;
    func.tags = [tag];
    func.dependencies = dependency ? [dependency] : undefined;

    return func;
};

export const runPendingDeployments = async () => {
    const { tag } = deploymentMetadata(getLatestDeploymentTag());

    return run(tag, {
        resetMemory: false,
        deletePreviousDeployments: false,
        writeDeploymentsToFiles: true
    });
};

export const getInstanceNameByAddress = (address: string): InstanceName => {
    const externalDeployments = config.external?.deployments![getNetworkName()];
    const deploymentsPath = externalDeployments ? externalDeployments[0] : path.join('deployments', getNetworkName());

    const deploymentPaths = glob.sync(`${deploymentsPath}/**/*.json`);
    for (const deploymentPath of deploymentPaths) {
        const name = path.basename(deploymentPath).split('.')[0];
        if (name.endsWith('_Implementation') || name.endsWith('_Proxy')) {
            continue;
        }

        const deployment: DeploymentData = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'));
        if (deployment.address.toLowerCase() === address.toLowerCase()) {
            return name as InstanceName;
        }
    }

    throw new Error(`Unable to find deployment for ${address}`);
};
