import { deployProxy, execute, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
import { VOUCHER_URI } from '../../../utils/Constants';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();

    await deployProxy(
        {
            name: InstanceName.Voucher,
            from: deployer
        },
        {
            args: [true, VOUCHER_URI, '']
        }
    );

    // Call post upgrade (required once per deployment)
    await execute({
        name: InstanceName.Voucher,
        methodName: 'postUpgrade',
        args: ["0x"],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
