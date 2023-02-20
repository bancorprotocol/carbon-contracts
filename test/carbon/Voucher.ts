import Contracts, { Voucher } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { createSystem } from '../helpers/Factory';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Voucher', () => {
    let nonAdmin: SignerWithAddress;
    let voucher: Voucher;

    before(async () => {
        [, nonAdmin] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ voucher } = await createSystem());
    });

    it('initializes', async () => {
        await expect(await voucher.symbol()).to.eq('CARBON-STRAT');
        await expect(await voucher.name()).to.eq('Carbon Automated Trading Strategy');
    });

    it('reverts when it is not the carbonController attempting to mint', async () => {
        await expect(voucher.mint(nonAdmin.address, 1)).to.be.revertedWithError('AccessDenied');
    });

    it('reverts when it is not the carbonController attempting to burn', async () => {
        await expect(voucher.burn(nonAdmin.address)).to.be.revertedWithError('AccessDenied');
    });

    it('reverts when a non owner tries to set carbonController', async () => {
        await expect(voucher.connect(nonAdmin).setCarbonController(ZERO_ADDRESS)).to.be.revertedWithError(
            'Ownable: caller is not the owner'
        );
    });

    it('reverts when trying to set the carbon controller with an invalid address', async () => {
        const voucher = await Contracts.Voucher.deploy(true, '', '');
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

    it('emits BaseURIUpdated event', async () => {
        const res = await voucher.setBaseURI('123');
        await expect(res).to.emit(voucher, 'BaseURIUpdated').withArgs('123');
    });

    it('emits BaseExtensionUpdated event', async () => {
        const res = await voucher.setBaseExtension('123');
        await expect(res).to.emit(voucher, 'BaseExtensionUpdated').withArgs('123');
    });

    it('emits UseGlobalURIUpdated event', async () => {
        const res = await voucher.useGlobalURI(true);
        await expect(res).to.emit(voucher, 'UseGlobalURIUpdated').withArgs(true);
    });
});
