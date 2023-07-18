import { CarbonController, TestVoucher } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { expectRole, expectRoles, Roles } from '../helpers/AccessControl';
import { createSystem } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Voucher', () => {
    let deployer: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let nonAdmin2: SignerWithAddress;
    let carbonController: CarbonController;
    let voucher: TestVoucher;

    shouldHaveGap('Voucher', '_useGlobalURI');

    before(async () => {
        [deployer, nonAdmin, nonAdmin2] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ carbonController, voucher } = await createSystem());
    });

    it('initializes', async () => {
        expect(await voucher.version()).to.equal(1);

        await expectRoles(voucher, Roles.Voucher);

        await expectRole(voucher, Roles.Upgradeable.ROLE_ADMIN, Roles.Upgradeable.ROLE_ADMIN, [deployer.address]);
        await expectRole(voucher, Roles.Voucher.ROLE_MINTER, Roles.Upgradeable.ROLE_ADMIN, [carbonController.address]);

        expect(await voucher.symbol()).to.eq('CARBON-STRAT');
        expect(await voucher.name()).to.eq('Carbon Automated Trading Strategy');
    });

    it('should revert when attempting to reinitialize', async () => {
        await expect(voucher.initialize(true, '', '')).to.be.revertedWithError(
            'Initializable: contract is already initialized'
        );
    });

    it('reverts when attempting to mint without the minter role', async () => {
        await expect(voucher.mint(nonAdmin.address, 1)).to.be.revertedWithError('AccessDenied');
    });

    it('reverts when attempting to burn without the minter role', async () => {
        await expect(voucher.burn(1)).to.be.revertedWithError('AccessDenied');
    });

    it('reverts when a non admin tries to update the base URI', async () => {
        const tx = voucher.connect(nonAdmin).setBaseURI('123');
        await expect(tx).to.have.been.revertedWithError('AccessDenied');
    });

    it('reverts when a non admin tries to update the extension URI', async () => {
        const tx = voucher.connect(nonAdmin).setBaseExtension('123');
        await expect(tx).to.have.been.revertedWithError('AccessDenied');
    });

    it('reverts when a non admin tries to call useGlobalUri', async () => {
        const tx = voucher.connect(nonAdmin).useGlobalURI(false);
        await expect(tx).to.have.been.revertedWithError('AccessDenied');
    });

    it('emits BaseURIUpdated event', async () => {
        const res = await voucher.setBaseURI('123');
        await expect(res).to.emit(voucher, 'BaseURIUpdated').withArgs('123');
    });

    it('emits BaseExtensionUpdated event', async () => {
        const res = await voucher.setBaseExtension('123');
        await expect(res).to.emit(voucher, 'BaseExtensionUpdated').withArgs('123');
    });

    it('emits UseGlobalURIUpdated event', async () => {
        const res = await voucher.useGlobalURI(false);
        await expect(res).to.emit(voucher, 'UseGlobalURIUpdated').withArgs(false);
    });

    it('does not emit the UseGlobalURIUpdated event if an update was attempted with the current value', async () => {
        await voucher.useGlobalURI(true);
        const res = await voucher.useGlobalURI(true);
        await expect(res).to.not.emit(voucher, 'UseGlobalURIUpdated');
    });

    it('should support erc-721 interface', async () => {
        const erc721InterfaceId = '0x80ac58cd';
        expect(await voucher.supportsInterface(erc721InterfaceId)).to.eq(true);
    });

    it('returns empty string if base uri is empty and not using global uri', async () => {
        await voucher.useGlobalURI(false);
        await voucher.setBaseURI('');
        // mint one token
        await voucher.safeMintTest(nonAdmin.address, 0);
        expect(await voucher.tokenURI(0)).to.eq('');
    });

    it('should be able to transfer voucher token', async () => {
        // mint one token
        await voucher.safeMintTest(nonAdmin.address, 0);
        expect(await voucher.balanceOf(nonAdmin.address)).to.eq(1);
        await expect(
            voucher
                .connect(nonAdmin)
                ['safeTransferFrom(address,address,uint256)'](nonAdmin.address, nonAdmin2.address, 0)
        ).not.to.be.reverted;
        expect(await voucher.balanceOf(nonAdmin.address)).to.eq(0);
        expect(await voucher.balanceOf(nonAdmin2.address)).to.eq(1);
    });

    it("transferring voucher token to same address shouldn't change balance", async () => {
        // mint one token
        await voucher.safeMintTest(nonAdmin.address, 0);
        expect(await voucher.balanceOf(nonAdmin.address)).to.eq(1);
        await expect(
            voucher
                .connect(nonAdmin)
                ['safeTransferFrom(address,address,uint256)'](nonAdmin.address, nonAdmin.address, 0)
        ).not.to.be.reverted;
        expect(await voucher.balanceOf(nonAdmin.address)).to.eq(1);
        expect(await voucher.balanceOf(nonAdmin2.address)).to.eq(0);
    });

    describe('tokens by owner', () => {
        const FETCH_AMOUNT = 5;

        it('reverts for non valid owner address', async () => {
            const tx = voucher.tokensByOwner(ZERO_ADDRESS, 0, 100);
            await expect(tx).to.be.revertedWithError('InvalidAddress');
        });

        it('fetches the correct tokenIds', async () => {
            await voucher.safeMintTest(nonAdmin.address, 1);
            await voucher.safeMintTest(nonAdmin.address, 2);
            await voucher.safeMintTest(nonAdmin2.address, 3);

            const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
            expect(tokenIds.length).to.eq(2);
            expect(tokenIds[0].toNumber()).to.eq(1);
            expect(tokenIds[1].toNumber()).to.eq(2);
        });

        it('sets endIndex to the maximum possible if provided with 0', async () => {
            for (let i = 1; i <= FETCH_AMOUNT; i++) {
                await voucher.safeMintTest(nonAdmin.address, i);
            }
            const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 0);
            expect(tokenIds.length).to.eq(FETCH_AMOUNT);
        });

        it('sets endIndex to the maximum possible if provided with an out of bound value', async () => {
            for (let i = 1; i < FETCH_AMOUNT + 1; i++) {
                await voucher.safeMintTest(nonAdmin.address, i);
            }
            const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, FETCH_AMOUNT + 100);
            expect(tokenIds.length).to.eq(FETCH_AMOUNT);
        });

        it('reverts if startIndex is greater than endIndex', async () => {
            for (let i = 1; i < FETCH_AMOUNT + 1; i++) {
                await voucher.safeMintTest(nonAdmin.address, i);
            }
            const tx = voucher.tokensByOwner(nonAdmin.address, 6, 5);
            await expect(tx).to.have.been.revertedWithError('InvalidIndices');
        });
    });

    it('maps owner when minting', async () => {
        await voucher.safeMintTest(nonAdmin.address, 1);
        const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
        expect(tokenIds[0]).to.eq(1);
    });

    it('clears owner mapping when burning', async () => {
        await voucher.safeMintTest(nonAdmin.address, 1);
        await voucher.burnTest(1);
        const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
        expect(tokenIds.length).to.eq(0);
    });
});
