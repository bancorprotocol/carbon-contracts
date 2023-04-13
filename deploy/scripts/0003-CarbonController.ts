import { ZERO_ADDRESS } from '../../utils/Constants';
import {
    DeployedContracts,
    deployProxy,
    grantRole,
    InstanceName,
    setDeploymentMetadata,
    upgradeProxy
} from '../../utils/Deploy';
import { Roles } from '../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer } = await getNamedAccounts();
    const voucher = await DeployedContracts.Voucher.deployed();

    await deployProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [voucher.address, ZERO_ADDRESS]
    });

    // immediate upgrade is required to set the proxy address in OnlyProxyDelegate
    const carbonController = await DeployedContracts.CarbonController.deployed();
    await upgradeProxy({
        name: InstanceName.CarbonController,
        from: deployer,
        args: [voucher.address, carbonController.address],
        initImpl: true
    });

    await grantRole({
        name: InstanceName.Voucher,
        id: Roles.Voucher.ROLE_MINTER,
        member: carbonController.address,
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
