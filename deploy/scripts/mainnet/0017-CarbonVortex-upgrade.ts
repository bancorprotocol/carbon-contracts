import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployedContracts, upgradeProxy, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
import { NATIVE_TOKEN_ADDRESS } from '../../../utils/Constants';

/**
 * upgrade carbon vortex 2.0 to v3:
 * remove the old vortex dependency
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt, vault } = await getNamedAccounts();
    const carbonController = await DeployedContracts.CarbonController.deployed();

    await upgradeProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [carbonController.address, vault, bnt, NATIVE_TOKEN_ADDRESS, bnt],
        checkVersion: false
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
