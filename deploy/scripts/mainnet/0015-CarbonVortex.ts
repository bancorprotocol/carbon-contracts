import { NATIVE_TOKEN_ADDRESS } from '../../../utils/TokenData';
import { DeployedContracts, deployProxy, grantRole, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
import { Roles } from '../../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

/**
 * deploy a new instance of carbon vortex v2.0 with the following configuration:
 *
 * 1. target token is ETH
 * 2. final target token is BNT
 * 3. transferAddress is BNT (will burn BNT tokens on ETH -> BNT trades)
 * 4. CarbonController and Vortex 1.0 are set as withdraw addresses (on execute, tokens will be withdrawn from both)
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt, vault, oldVortex } = await getNamedAccounts();
    const carbonController = await DeployedContracts.CarbonController.deployed();

    await deployProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [carbonController.address, vault, oldVortex, bnt, NATIVE_TOKEN_ADDRESS, bnt]
    });

    const carbonVortex = await DeployedContracts.CarbonVortex.deployed();

    await grantRole({
        name: InstanceName.CarbonController,
        id: Roles.CarbonController.ROLE_FEES_MANAGER,
        member: carbonVortex.address,
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
