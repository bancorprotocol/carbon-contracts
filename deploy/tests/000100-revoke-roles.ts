import { AccessControlEnumerableUpgradeable } from '../../components/Contracts';
import { describeDeployment } from '../../utils/helpers/Deploy';
import { DeployedContracts, isLive } from '../../utils/Deploy';
import { expect } from 'chai';
import { getNamedAccounts } from 'hardhat';
import { Roles } from '../../utils/Roles';

describeDeployment(__filename, () => {
    let deployer: string;
    let daoMultisig: string;

    beforeEach(async () => {
        ({ deployer, daoMultisig } = await getNamedAccounts());
    });

    it('should revoke deployer roles', async () => {
        // get contracts
        const carbon = (await DeployedContracts.CarbonController.deployed()) as AccessControlEnumerableUpgradeable;
        const voucher = (await DeployedContracts.Voucher.deployed()) as AccessControlEnumerableUpgradeable;
        const feeBurner = (await DeployedContracts.FeeBurner.deployed()) as AccessControlEnumerableUpgradeable;

        // expect dao multisig to have the admin role for all contracts
        expect(await carbon.hasRole(Roles.Upgradeable.ROLE_ADMIN, daoMultisig)).to.be.true;
        expect(await voucher.hasRole(Roles.Upgradeable.ROLE_ADMIN, daoMultisig)).to.be.true;
        expect(await feeBurner.hasRole(Roles.Upgradeable.ROLE_ADMIN, daoMultisig)).to.be.true;
        
        // expect deployer not to have the admin role for all contracts
        expect(await carbon.hasRole(Roles.Upgradeable.ROLE_ADMIN, deployer)).to.be.false;
        expect(await voucher.hasRole(Roles.Upgradeable.ROLE_ADMIN, deployer)).to.be.false;
        expect(await feeBurner.hasRole(Roles.Upgradeable.ROLE_ADMIN, deployer)).to.be.false;

        // expect deployer not to have the emergency stopper role
        expect(await carbon.hasRole(Roles.CarbonController.ROLE_EMERGENCY_STOPPER, deployer)).to.be.false;
        // expect deployer not to have the fee manager role
        expect(await carbon.hasRole(Roles.CarbonController.ROLE_FEES_MANAGER, deployer)).to.be.false;
    });
},
    
{ skip: isLive }
);
