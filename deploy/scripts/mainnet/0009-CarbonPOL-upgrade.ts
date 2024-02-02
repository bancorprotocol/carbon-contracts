import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { upgradeProxy, InstanceName, setDeploymentMetadata, execute } from '../../../utils/Deploy';
import { toWei } from '../../../utils/Types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, bnt } = await getNamedAccounts();

    await upgradeProxy({
        name: InstanceName.CarbonPOL,
        from: deployer,
        args: [bnt]
    });

    // Set ETH sale amount to 100 ether
    await execute({
        name: InstanceName.CarbonPOL,
        methodName: 'setEthSaleAmount',
        args: [toWei(100)],
        from: deployer
    });

    // Set min ETH sale amount to 10 ether
    await execute({
        name: InstanceName.CarbonPOL,
        methodName: 'setMinEthSaleAmount',
        args: [toWei(10)],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
