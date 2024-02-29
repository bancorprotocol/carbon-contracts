import { deployProxy, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
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

    return true;
};

export default setDeploymentMetadata(__filename, func);
