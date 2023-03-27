import Contracts, { TestVoucher } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { createProxy, createSystem } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Voucher', () => {
    let nonAdmin: SignerWithAddress;
    let nonAdmin2: SignerWithAddress;
    let voucher: TestVoucher;

    shouldHaveGap('Voucher', '_carbonController');

    before(async () => {
        [, nonAdmin, nonAdmin2] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ voucher } = await createSystem());
    });

    it('initializes', async () => {
        expect(await voucher.version()).to.equal(1);

        await expect(await voucher.symbol()).to.eq('CARBON-STRAT');
        await expect(await voucher.name()).to.eq('Carbon Automated Trading Strategy');
    });

    it('reverts when it is not the carbonController attempting to mint', async () => {
        await expect(voucher.mint(nonAdmin.address, 1)).to.be.revertedWithError('AccessDenied');
    });

    it('reverts when it is not the carbonController attempting to burn', async () => {
        await expect(voucher.burn(1)).to.be.revertedWithError('AccessDenied');
    });

    it('reverts when a non owner tries to set carbonController', async () => {
        await expect(voucher.connect(nonAdmin).setCarbonController(ZERO_ADDRESS)).to.be.revertedWithError(
            'Ownable: caller is not the owner'
        );
    });

    it('reverts when trying to set the carbon controller with an invalid address', async () => {
        const voucher = await createProxy(Contracts.Voucher, {
            initArgs: [true, '', '']
        });
        const tx = voucher.setCarbonController(ZERO_ADDRESS);
        await expect(tx).to.have.been.revertedWithError('InvalidAddress');
    });

    it('reverts when a non owner tries to update the base URI', async () => {
        const tx = voucher.connect(nonAdmin).setBaseURI('123');
        await expect(tx).to.have.been.revertedWithError('Ownable: caller is not the owner');
    });

    it('reverts when a non owner tries to update the extension URI', async () => {
        const tx = voucher.connect(nonAdmin).setBaseExtension('123');
        await expect(tx).to.have.been.revertedWithError('Ownable: caller is not the owner');
    });

    it('emits CarbonControllerUpdated event', async () => {
        const res = await voucher.setCarbonController(voucher.address);
        await expect(res).to.emit(voucher, 'CarbonControllerUpdated').withArgs(voucher.address);
    });

    it('does not emit the CarbonControllerUpdated event if an update was attempted with the current value', async () => {
        await voucher.setCarbonController(voucher.address);
        const res = await voucher.setCarbonController(voucher.address);
        await expect(res).to.not.emit(voucher, 'CarbonControllerUpdated');
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

    describe('tokens by owner', () => {
        const FETCH_AMOUNT = 5;

        it('reverts for non valid owner address', async () => {
            const tx = voucher.tokensByOwner(ZERO_ADDRESS, 0, 100);
            await expect(tx).to.be.revertedWithError('InvalidAddress');
        });

        it('fetches the correct tokenIds', async () => {
            await voucher.testSafeMint(nonAdmin.address, 1);
            await voucher.testSafeMint(nonAdmin.address, 2);
            await voucher.testSafeMint(nonAdmin2.address, 3);

            const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
            expect(tokenIds.length).to.eq(2);
            expect(tokenIds[0].toNumber()).to.eq(1);
            expect(tokenIds[1].toNumber()).to.eq(2);
        });

        it('sets endIndex to the maximum possible if provided with 0', async () => {
            for (let i = 1; i <= FETCH_AMOUNT; i++) {
                await voucher.testSafeMint(nonAdmin.address, i);
            }
            const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 0);
            expect(tokenIds.length).to.eq(FETCH_AMOUNT);
        });

        it('sets endIndex to the maximum possible if provided with an out of bound value', async () => {
            for (let i = 1; i < FETCH_AMOUNT + 1; i++) {
                await voucher.testSafeMint(nonAdmin.address, i);
            }
            const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, FETCH_AMOUNT + 100);
            expect(tokenIds.length).to.eq(FETCH_AMOUNT);
        });

        it('reverts if startIndex is greater than endIndex', async () => {
            for (let i = 1; i < FETCH_AMOUNT + 1; i++) {
                await voucher.testSafeMint(nonAdmin.address, i);
            }
            const tx = voucher.tokensByOwner(nonAdmin.address, 6, 5);
            await expect(tx).to.have.been.revertedWithError('InvalidIndices');
        });
    });

    it('maps owner when minting', async () => {
        await voucher.testSafeMint(nonAdmin.address, 1);
        const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
        expect(tokenIds[0]).to.eq(1);
    });

    it('clears owner mapping when burning', async () => {
        await voucher.testSafeMint(nonAdmin.address, 1);
        await voucher.testBurn(1);
        const tokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
        expect(tokenIds.length).to.eq(0);
    });
});
