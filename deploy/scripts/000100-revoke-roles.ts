import {
    grantRole,
    InstanceName,
    isLive,
    renounceRole,
    revokeRole,
    setDeploymentMetadata
} from '../../utils/Deploy';
import { Roles } from '../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, daoMultisig } = await getNamedAccounts();

    // Grant CarbonController admin roles to dao multisig
    await grantRole({
        name: InstanceName.CarbonController,
        id: Roles.Upgradeable.ROLE_ADMIN,
        member: daoMultisig,
        from: deployer
    });

    await revokeRole({
        name: InstanceName.CarbonController,
        id: Roles.Upgradeable.ROLE_ADMIN,
        member: deployer,
        from: deployer
    });

    // Grant Voucher admin roles to dao multisig
    await grantRole({
        name: InstanceName.Voucher,
        id: Roles.Upgradeable.ROLE_ADMIN,
        member: daoMultisig,
        from: deployer
    });

    await revokeRole({
        name: InstanceName.Voucher,
        id: Roles.Upgradeable.ROLE_ADMIN,
        member: deployer,
        from: deployer
    });

    // Grant FeeBurner admin roles to dao multisig
    await grantRole({
        name: InstanceName.FeeBurner,
        id: Roles.Upgradeable.ROLE_ADMIN,
        member: daoMultisig,
        from: deployer
    });

    await revokeRole({
        name: InstanceName.FeeBurner,
        id: Roles.Upgradeable.ROLE_ADMIN,
        member: deployer,
        from: deployer
    });

    // renounce CarbonController's ROLE_EMERGENCY_STOPPER role from the deployer
    await renounceRole({
        name: InstanceName.CarbonController,
        id: Roles.CarbonController.ROLE_EMERGENCY_STOPPER,
        from: deployer
    });

    // renounce CarbonController's ROLE_FEES_MANAGER role from the deployer
    await renounceRole({
        name: InstanceName.CarbonController,
        id: Roles.CarbonController.ROLE_FEES_MANAGER,
        from: deployer
    });

    return true;
};

// postpone the execution of this script to the end of the beta
func.skip = async () => isLive();

export default setDeploymentMetadata(__filename, func);
