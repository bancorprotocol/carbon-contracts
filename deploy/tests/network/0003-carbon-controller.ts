import { CarbonController, ProxyAdmin } from '../../../components/Contracts';
import { DeployedContracts, describeDeployment } from '../../../utils/Deploy';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let carbonController: CarbonController;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        carbonController = await DeployedContracts.CarbonController.deployed();
    });

    it('should deploy and configure the carbon controller contract', async () => {
        expect(await proxyAdmin.getProxyAdmin(carbonController.address)).to.equal(proxyAdmin.address);
        expect(await carbonController.version()).to.equal(6);
    });

    it('carbon controller implementation should be initialized', async () => {
        const implementationAddress = await proxyAdmin.getProxyImplementation(carbonController.address);
        const carbonControllerImpl: CarbonController = await ethers.getContractAt(
            'CarbonController',
            implementationAddress
        );
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await carbonControllerImpl.initialize({ gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });

    it('cannot call postUpgrade on carbon controller', async () => {
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await carbonController.postUpgrade(true, '0x', { gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });
});
