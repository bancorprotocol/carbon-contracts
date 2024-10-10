import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployedContracts, upgradeProxy, InstanceName, setDeploymentMetadata, execute } from '../../../utils/Deploy';
import { NATIVE_TOKEN_ADDRESS } from '../../../utils/Constants';

/**
 * upgrade carbon vortex 2.0 to v4:
 * remove the old vortex dependency
 * fix final target token execute call to send funds to transfer address
 * make transfer address a settable variable
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt, vault } = await getNamedAccounts();
    const carbonController = await DeployedContracts.CarbonController.deployed();

    await upgradeProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [carbonController.address, vault, NATIVE_TOKEN_ADDRESS, bnt],
        checkVersion: false,
        proxy: {
            args: [bnt]
        }
    });

    // Set the transfer address to BNT in the vortex contract
    await execute({
        name: InstanceName.CarbonVortex,
        methodName: 'setTransferAddress',
        args: [bnt],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
