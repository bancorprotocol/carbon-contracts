import { deployProxy, InstanceName, setDeploymentMetadata } from '../../utils/Deploy';
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
            args: [true, 'ipfs://QmNmM9iSZt4FK3HZWMadboQ4nB1W3tjyZDeqyZ9g4xesAt', '']
        }
    );

    return true;
};

export default setDeploymentMetadata(__filename, func);
