import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { upgradeProxy, InstanceName, setDeploymentMetadata, execute, DeployedContracts } from '../../../utils/Deploy';
import { ZERO_ADDRESS } from '../../../utils/Constants';

/**
 * upgrade carbon vortex 2.0 to v5:
 * add support for multiple controllers
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    let { deployer, vault, targetToken, finalTargetToken, transferAddress } = await getNamedAccounts();

    if (finalTargetToken === undefined) {
        finalTargetToken = ZERO_ADDRESS;
    }
    if (transferAddress === undefined) {
        transferAddress = ZERO_ADDRESS;
    }

    await upgradeProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [vault, targetToken, finalTargetToken],
        checkVersion: true
    });

    const carbonController = await DeployedContracts.CarbonController.deployed();

    // Add carbon controller to the list of controller addresses
    await execute({
        name: InstanceName.CarbonVortex,
        methodName: 'addController',
        args: [carbonController.address],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
