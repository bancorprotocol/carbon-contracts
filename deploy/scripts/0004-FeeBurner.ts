import { DeployedContracts, deployProxy, grantRole, InstanceName, setDeploymentMetadata } from '../../utils/Deploy';
import { Roles } from '../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt, bancorNetworkV3 } = await getNamedAccounts();
    const carbonController = await DeployedContracts.CarbonController.deployed();

    await deployProxy(
        {
            name: InstanceName.FeeBurner,
            from: deployer,
            args: [bnt, carbonController.address, bancorNetworkV3]
        },
        {
            initImpl: true
        }
    );

    const feeBurner = await DeployedContracts.FeeBurner.deployed();

    await grantRole({
        name: InstanceName.CarbonController,
        id: Roles.CarbonController.ROLE_FEES_MANAGER,
        member: feeBurner.address,
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
