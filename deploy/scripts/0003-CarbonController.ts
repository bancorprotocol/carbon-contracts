import { ZERO_ADDRESS } from '../../utils/Constants';
import {
    DeployedContracts,
    deployProxy,
    execute,
    InstanceName,
    setDeploymentMetadata,
    upgradeProxy
} from '../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();
    const voucher = await DeployedContracts.Voucher.deployed();

    await deployProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [voucher.address, ZERO_ADDRESS]
    });

    // immediate upgrade is required to set the proxy address in OnlyProxyDelegate
    const carbonController = await DeployedContracts.CarbonController.deployed();
    await upgradeProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [voucher.address, carbonController.address]
    });

    await execute({
        name: InstanceName.Voucher,
        methodName: 'setController',
        args: [carbonController.address],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
