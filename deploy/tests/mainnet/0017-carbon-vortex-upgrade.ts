import { CarbonVortex, ProxyAdmin } from '../../../components/Contracts';
import { DeployedContracts, describeDeployment } from '../../../utils/Deploy';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let carbonVortex: CarbonVortex;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        carbonVortex = await DeployedContracts.CarbonVortex.deployed();
    });

    it('should deploy and configure the carbon vortex contract', async () => {
        expect(await proxyAdmin.getProxyAdmin(carbonVortex.address)).to.equal(proxyAdmin.address);
        expect(await carbonVortex.version()).to.equal(3);
    });

    it('carbon vortex implementation should be initialized', async () => {
        const implementationAddress = await proxyAdmin.getProxyImplementation(carbonVortex.address);
        const carbonControllerImpl: CarbonVortex = await ethers.getContractAt('CarbonVortex', implementationAddress);
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await carbonControllerImpl.initialize({ gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });

    it('cannot call postUpgrade on carbon vortex', async () => {
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await carbonVortex.postUpgrade(true, '0x', { gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });
});
