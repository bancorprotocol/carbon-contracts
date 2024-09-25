import { ZERO_ADDRESS } from '../../../utils/Constants';
import { DeployedContracts, deployProxy, grantRole, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
import { Roles } from '../../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

/**
 * deploy a new instance of carbon vortex v2.0 with the following configuration:
 *
 * 1. target token is *targetToken* - set address in named-accounts VortexNamedAccounts for the chain
 * 2. final target token is *finalTargetToken* - set address in named-accounts VortexNamedAccounts for the chain (can be zero address)
 * 3. transferAddress is *transferAddress* - set address in named-accounts VortexNamedAccounts for the chain
 *    --- this is the address that will receive the target / final target tokens after trade
 * 4. CarbonController is set as withdraw address (on execute, tokens will be withdrawn from it
 * 5. For licensed deployments, vault should be address 0 (already configured)
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, targetToken, finalTargetToken, transferAddress } = await getNamedAccounts();
    const carbonController = await DeployedContracts.CarbonController.deployed();

    await deployProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [carbonController.address, ZERO_ADDRESS, transferAddress, targetToken, finalTargetToken]
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
