import { DeployedContracts, InstanceName, setDeploymentMetadata, upgradeProxy } from '../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();
    const voucher = await DeployedContracts.Voucher.deployed();

    const carbonController = await DeployedContracts.CarbonController.deployed();
    await upgradeProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [voucher.address, carbonController.address],
        initImpl: true
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
