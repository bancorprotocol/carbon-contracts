import { deploy, DeployedContracts, grantRole, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { Roles } from '../../../utils/Roles';

/**
 * @dev deploy vault and grant asset manager role to the vortex
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();

    await deploy({
        name: InstanceName.Vault,
        from: deployer,
        args: []
    });

    const carbonVortex = await DeployedContracts.CarbonVortex.deployed();

    // grant asset manager role to carbon vortex
    await grantRole({
        name: InstanceName.Vault,
        id: Roles.Vault.ROLE_ASSET_MANAGER,
        member: carbonVortex.address,
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
