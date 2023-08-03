import { DeployedContracts, InstanceName, setDeploymentMetadata, upgradeProxy } from '../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt, bancorNetworkV3 } = await getNamedAccounts();

    const carbonController = await DeployedContracts.CarbonController.deployed();

    await upgradeProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [bnt, carbonController.address, bancorNetworkV3]
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
