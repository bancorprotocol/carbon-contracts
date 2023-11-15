import { upgradeProxy, InstanceName, setDeploymentMetadata } from '../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt } = await getNamedAccounts();

    await upgradeProxy({
        name: InstanceName.CarbonPOL,
        from: deployer,
        args: [bnt]
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
