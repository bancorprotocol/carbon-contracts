import { CarbonController, FeeBurner, ProxyAdmin } from '../../components/Contracts';
import { DeployedContracts } from '../../utils/Deploy';
import { describeDeployment } from '../../utils/helpers/Deploy';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let carbonController: CarbonController;
    let feeBurner: FeeBurner;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        carbonController = await DeployedContracts.CarbonController.deployed();
        feeBurner = await DeployedContracts.FeeBurner.deployed();
    });

    it('should deploy and configure the fee burner contract', async () => {
        expect(await proxyAdmin.getProxyAdmin(feeBurner.address)).to.equal(proxyAdmin.address);
        expect(await feeBurner.version()).to.equal(1);

        // check that the fee burner is the fee manager
        const role = await carbonController.roleFeesManager();
        const roleMembers = await carbonController.getRoleMemberCount(role);
        const feeManagers = [];
        for (let i = 0; i < roleMembers.toNumber(); ++i) {
            const feeManagerAddress = await carbonController.getRoleMember(role, i);
            feeManagers.push(feeManagerAddress);
        }
        expect(feeManagers.includes(feeBurner.address)).to.be.true;
    });

    it('fee burner implementation should be initialized', async () => {
        const implementationAddress = await proxyAdmin.getProxyImplementation(feeBurner.address);
        const feeBurnerImpl: FeeBurner = await ethers.getContractAt('FeeBurner', implementationAddress);
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await feeBurnerImpl.initialize({ gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });
});
