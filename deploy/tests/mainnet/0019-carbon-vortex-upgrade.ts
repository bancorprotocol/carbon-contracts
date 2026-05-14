import { CarbonController, CarbonVortex, ProxyAdmin } from '../../../components/Contracts';
import { DeployedContracts, describeDeployment, fundAccount, getNamedSigners } from '../../../utils/Deploy';
import { Roles } from '../../../utils/Roles';
import { getBalance } from '../../../test/helpers/Utils';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, getNamedAccounts } from 'hardhat';

describeDeployment(__filename, () => {
    let proxyAdmin: ProxyAdmin;
    let carbonController: CarbonController;
    let carbonVortex: CarbonVortex;

    beforeEach(async () => {
        proxyAdmin = await DeployedContracts.ProxyAdmin.deployed();
        carbonController = await DeployedContracts.CarbonController.deployed();
        carbonVortex = await DeployedContracts.CarbonVortex.deployed();
    });

    it('vortex should be at v5 with controller wired up for fee withdrawal', async () => {
        expect(await proxyAdmin.getProxyAdmin(carbonVortex.address)).to.equal(proxyAdmin.address);
        expect(await carbonVortex.version()).to.equal(5);

        expect(await carbonController.hasRole(Roles.CarbonController.ROLE_FEES_MANAGER, carbonVortex.address)).to.equal(
            true
        );

        expect(await carbonVortex.controllers()).to.include(carbonController.address);
    });

    it('execute() should withdraw accumulated fees from the controller via the new FEES_MANAGER role', async () => {
        const { deployer } = await getNamedSigners();
        await fundAccount(deployer);

        const { usdc, dai, wbtc, link, vault } = await getNamedAccounts();
        // Use non-target / non-final-target tokens so the vortex retains them after execute()
        // (target/final-target tokens get forwarded to transferAddress or burned via the auction logic).
        const candidates = [usdc, dai, wbtc, link];

        let token: string | null = null;
        let controllerFeesBefore = BigNumber.from(0);
        for (const addr of candidates) {
            const fees = await carbonController.accumulatedFees(addr);
            if (fees.gt(0)) {
                token = addr;
                controllerFeesBefore = fees;
                break;
            }
        }

        if (!token) {
            // No accumulated fees on this fork; still exercise the path to confirm it executes without reverting.
            await (await carbonVortex.connect(deployer).execute([usdc])).wait();
            return;
        }

        const tokenContract = await ethers.getContractAt('TestERC20Burnable', token);
        const vaultBalanceBefore = await getBalance(tokenContract, vault);
        const vortexBalanceBefore = await getBalance(tokenContract, carbonVortex.address);
        const callerBalanceBefore = await getBalance(tokenContract, deployer.address);

        await carbonVortex.connect(deployer).execute([token]);

        // Core assertion: the FEES_MANAGER role works — the controller's accumulated fees were withdrawn.
        expect(await carbonController.accumulatedFees(token)).to.equal(0);

        // execute() also pulls the token balance from the vault (vortex has ROLE_ASSET_MANAGER there)
        expect(await getBalance(tokenContract, vault)).to.equal(0);

        // Caller receives `rewardsPPM` of the total withdrawn; the vortex retains the rest for the auction.
        const rewardsPPM = await carbonVortex.rewardsPPM();
        const PPM = BigNumber.from(1_000_000);
        const totalWithdrawn = controllerFeesBefore.add(vaultBalanceBefore);
        const expectedReward = totalWithdrawn.mul(rewardsPPM).div(PPM);
        const expectedVortexDelta = totalWithdrawn.sub(expectedReward);

        const callerDelta = (await getBalance(tokenContract, deployer.address)).sub(callerBalanceBefore);
        const vortexDelta = (await getBalance(tokenContract, carbonVortex.address)).sub(vortexBalanceBefore);

        expect(callerDelta).to.equal(expectedReward);
        expect(vortexDelta).to.equal(expectedVortexDelta);
    });
});
