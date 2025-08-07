import { ethers } from 'hardhat/internal/lib/hardhat-lib';
import { ZERO_ADDRESS } from '../../../utils/Constants';
import { DeployedContracts, deployProxy, InstanceName, setDeploymentMetadata } from '../../../utils/Deploy';
import { Roles } from '../../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

/**
 * deploy a new instance of carbon vortex v2.0 with the following configuration:
 *
 * 1. target token is *targetToken* - set address in named-accounts VortexNamedAccounts for the chain
 * 2. final target token is *finalTargetToken* - set address in named-accounts VortexNamedAccounts for the chain (can be zero address)
 * 3. transferAddress is *transferAddress* - set address in named-accounts VortexNamedAccounts for the chain
 *    --- this is the address that will receive the target / final target tokens after trade
 * 4. Vault is set as withdraw address (on execute, tokens will be withdrawn from it)
 * 5. For support deployments, carbon controller should be address 0 (already configured)
 */
const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    let { deployer, vault, targetToken, finalTargetToken, transferAddress } = await getNamedAccounts();

    if (finalTargetToken === undefined) {
        finalTargetToken = ZERO_ADDRESS;
    }
    if (transferAddress === undefined) {
        transferAddress = ZERO_ADDRESS;
    }

    await deployProxy(
        {
            name: InstanceName.CarbonVortex,
            from: deployer,
            args: [ZERO_ADDRESS, vault, targetToken, finalTargetToken]
        },
        {
            args: [transferAddress]
        }
    );

    const carbonVortex = await DeployedContracts.CarbonVortex.deployed();

    const deployerSigner = await ethers.getSigner(deployer);
    const vaultContract = await ethers.getContractAt('CarbonController', vault);

    // grant asset manager role to the vortex from the vault contract
    await vaultContract.connect(deployerSigner).grantRole(Roles.Vault.ROLE_ASSET_MANAGER, carbonVortex.address);

    return true;
};

export default setDeploymentMetadata(__filename, func);
