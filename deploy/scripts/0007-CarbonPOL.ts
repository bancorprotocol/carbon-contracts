import { deployProxy, InstanceName, setDeploymentMetadata } from '../../utils/Deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, uniswapV3Router, uniswapV3Factory, uniswapV3Oracle, weth } = await getNamedAccounts();

    const twapPeriod = 1800; // 30 minutes

    await deployProxy({
        name: InstanceName.CarbonPOL,
        from: deployer,
        args: [uniswapV3Router, uniswapV3Factory, uniswapV3Oracle, weth, twapPeriod]
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
