import { CarbonController, CarbonVortex, ProxyAdmin } from '../../../components/Contracts';
import { DeployedContracts, describeDeployment } from '../../../utils/Deploy';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let carbonController: CarbonController;
    let carbonVortex: CarbonVortex;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        carbonController = await DeployedContracts.CarbonController.deployed();
        carbonVortex = await DeployedContracts.CarbonVortex.deployed();
    });

    it('should deploy and configure the fee burner contract', async () => {
        expect(await proxyAdmin.getProxyAdmin(carbonVortex.address)).to.equal(proxyAdmin.address);
        expect(await carbonVortex.version()).to.equal(1);

        // check that the fee burner is the fee manager
        const role = await carbonController.roleFeesManager();
        const roleMembers = await carbonController.getRoleMemberCount(role);
        const feeManagers = [];
        for (let i = 0; i < roleMembers.toNumber(); ++i) {
            const feeManagerAddress = await carbonController.getRoleMember(role, i);
            feeManagers.push(feeManagerAddress);
        }
        expect(feeManagers.includes(carbonVortex.address)).to.be.true;
    });

    it('fee burner implementation should be initialized', async () => {
        const implementationAddress = await proxyAdmin.getProxyImplementation(carbonVortex.address);
        const carbonVortexImpl: CarbonVortex = await ethers.getContractAt('CarbonVortex', implementationAddress);
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await carbonVortexImpl.initialize({ gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });
});
