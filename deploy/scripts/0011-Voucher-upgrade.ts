import { DeployedContracts, InstanceName, execute, setDeploymentMetadata, upgradeProxy } from '../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

/**
 * @dev voucher immutability upgrade - replace minter role with controller role
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();

    await upgradeProxy({
        name: InstanceName.Voucher,
        from: deployer,
        args: []
    });

    const controller = await DeployedContracts.CarbonController.deployed();

    // Set the carbon controller address in the voucher contract
    await execute({
        name: InstanceName.Voucher,
        methodName: 'setController',
        args: [controller.address],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
