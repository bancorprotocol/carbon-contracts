import { CarbonPOL, ProxyAdmin } from '../../components/Contracts';
import { DeployedContracts } from '../../utils/Deploy';
import { describeDeployment } from '../../utils/helpers/Deploy';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let carbonPOL: CarbonPOL;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        carbonPOL = await DeployedContracts.CarbonPOL.deployed();
    });

    it('should deploy and configure the carbon pol contract', async () => {
        expect(await proxyAdmin.getProxyAdmin(carbonPOL.address)).to.equal(proxyAdmin.address);
        expect(await carbonPOL.version()).to.equal(1);

        // check rewards ppm is configured correctly
        expect(await carbonPOL.rewardsPPM()).to.equal(2000);
        // check max slippage ppm is configured correctly
        expect(await carbonPOL.maxSlippagePPM()).to.equal(3000);
        // check max tradeable ppb is configured correctly
        expect(await carbonPOL.maxTradeablePPB()).to.equal(1389);
    });

    it('carbon pol implementation should be initialized', async () => {
        const implementationAddress = await proxyAdmin.getProxyImplementation(carbonPOL.address);
        const carbonPOLImpl: CarbonPOL = await ethers.getContractAt('CarbonPOL', implementationAddress);
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await carbonPOLImpl.initialize({ gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });
});
