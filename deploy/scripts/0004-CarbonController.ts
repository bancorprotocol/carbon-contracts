import { ZERO_ADDRESS } from '../../utils/Constants';
import {
    DeployedContracts,
    deployProxy,
    execute,
    grantRole,
    InstanceName,
    setDeploymentMetadata,
    upgradeProxy
} from '../../utils/Deploy';
import { Roles } from '../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();

    const masterVault = await DeployedContracts.MasterVault.deployed();
    const voucher = await DeployedContracts.Voucher.deployed();

    await deployProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [masterVault.address, voucher.address, ZERO_ADDRESS]
    });

    // immediate upgrade is required to set the proxy address in OnlyProxyDelegate
    const carbonController = await DeployedContracts.CarbonController.deployed();
    await upgradeProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [masterVault.address, voucher.address, carbonController.address]
    });

    await execute({
        name: InstanceName.Voucher,
        methodName: 'setCarbonController',
        args: [carbonController.address],
        from: deployer
    });

    await grantRole({
        name: InstanceName.MasterVault,
        id: Roles.Vault.ROLE_ASSET_MANAGER,
        member: carbonController.address,
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
