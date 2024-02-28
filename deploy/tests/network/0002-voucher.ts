import { ProxyAdmin, Voucher } from '../../../components/Contracts';
import { DeployedContracts, describeDeployment } from '../../../utils/Deploy';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let voucher: Voucher;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        voucher = await DeployedContracts.Voucher.deployed();
    });

    it('should deploy and configure the voucher contract', async () => {
        expect(await proxyAdmin.getProxyAdmin(voucher.address)).to.equal(proxyAdmin.address);
        expect(await voucher.version()).to.equal(2);
    });

    it('voucher implementation should be initialized', async () => {
        const implementationAddress = await proxyAdmin.getProxyImplementation(voucher.address);
        const voucherImpl: Voucher = await ethers.getContractAt('Voucher', implementationAddress);
        // hardcoding gas limit to avoid gas estimation attempts (which get rejected instead of reverted)
        const tx = await voucherImpl.initialize(true, '1', '1', { gasLimit: 6000000 });
        await expect(tx.wait()).to.be.reverted;
    });
});
