import Contracts, { CarbonController, Voucher } from '../../components/Contracts';
import { ControllerType, DEFAULT_TRADING_FEE_PPM, ZERO_ADDRESS } from '../../utils/Constants';
import { expectRole, expectRoles, Roles } from '../helpers/AccessControl';
import { createProxy, createSystem } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('CarbonController', () => {
    let deployer: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let emergencyStopper: SignerWithAddress;
    let carbonController: CarbonController;
    let voucher: Voucher;

    shouldHaveGap('CarbonController');

    before(async () => {
        [deployer, nonAdmin, emergencyStopper] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ carbonController, voucher } = await createSystem());
    });

    describe('construction', () => {
        it('should be properly initialized', async () => {
            expect(await carbonController.version()).to.equal(2);

            await expectRoles(carbonController, Roles.CarbonController);

            await expectRole(carbonController, Roles.Upgradeable.ROLE_ADMIN, Roles.Upgradeable.ROLE_ADMIN, [
                deployer.address
            ]);
            await expectRole(
                carbonController,
                Roles.CarbonController.ROLE_EMERGENCY_STOPPER,
                Roles.Upgradeable.ROLE_ADMIN
            );
            await expectRole(carbonController, Roles.CarbonController.ROLE_FEES_MANAGER, Roles.Upgradeable.ROLE_ADMIN);

            expect(await carbonController.controllerType()).to.equal(ControllerType.Standard);
            expect(await carbonController.tradingFeePPM()).to.equal(DEFAULT_TRADING_FEE_PPM);
        });
    });

    describe('pausing/unpausing', () => {
        beforeEach(async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_EMERGENCY_STOPPER, emergencyStopper.address);
        });

        it('pauses', async () => {
            const res = await carbonController.connect(emergencyStopper).pause();
            await expect(res).to.emit(carbonController, 'Paused').withArgs(emergencyStopper.address);
        });

        it('unpauses', async () => {
            await carbonController.connect(emergencyStopper).pause();
            const res = await carbonController.connect(emergencyStopper).unpause();
            await expect(res).to.emit(carbonController, 'Unpaused').withArgs(emergencyStopper.address);
            expect(await carbonController.paused()).to.be.false;
        });

        it('restricts pausing', async () => {
            await expect(carbonController.connect(nonAdmin).pause()).to.be.revertedWithError('AccessDenied');
        });

        it('restricts unpausing', async () => {
            await carbonController.connect(emergencyStopper).pause();
            await expect(carbonController.connect(nonAdmin).unpause()).to.be.revertedWithError('AccessDenied');
        });
    });

    it('reverts when querying accumulatedFees with an invalid address', async () => {
        await expect(carbonController.accumulatedFees(ZERO_ADDRESS)).to.be.revertedWithError('InvalidAddress');
    });

    describe('unknown delegator', () => {
        it('reverts when an unknown delegator tries creating a pair', async () => {
            const carbonController = await createProxy(Contracts.CarbonController, {
                skipInitialization: false,
                ctorArgs: [voucher.address, voucher.address]
            });
            const tx = carbonController.createPair(ZERO_ADDRESS, ZERO_ADDRESS);
            await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
        });

        it('reverts when an unknown delegator tries creating a strategy', async () => {
            const carbonController = await createProxy(Contracts.CarbonController, {
                skipInitialization: false,
                ctorArgs: [voucher.address, voucher.address]
            });
            const order = { y: 0, z: 0, A: 0, B: 0 };
            const tx = carbonController.createStrategy(ZERO_ADDRESS, ZERO_ADDRESS, [order, order]);
            await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
        });

        it('reverts when an unknown delegator tries updating a strategy', async () => {
            const carbonController = await createProxy(Contracts.CarbonController, {
                skipInitialization: false,
                ctorArgs: [voucher.address, voucher.address]
            });
            const order = { y: 0, z: 0, A: 0, B: 0 };
            const tx = carbonController.updateStrategy(1, [order, order], [order, order]);
            await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
        });

        it('reverts when an unknown delegator tries deleting a strategy', async () => {
            const carbonController = await createProxy(Contracts.CarbonController, {
                skipInitialization: false,
                ctorArgs: [voucher.address, voucher.address]
            });
            const tx = carbonController.deleteStrategy(1);
            await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
        });

        it('reverts when an unknown delegator tries trading by source mount', async () => {
            const carbonController = await createProxy(Contracts.CarbonController, {
                skipInitialization: false,
                ctorArgs: [voucher.address, voucher.address]
            });
            const tx = carbonController.tradeBySourceAmount(
                ZERO_ADDRESS,
                ZERO_ADDRESS,
                [{ strategyId: 1, amount: 1 }],
                1,
                1
            );
            await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
        });

        it('reverts when an unknown delegator tries trading by target mount', async () => {
            const carbonController = await createProxy(Contracts.CarbonController, {
                skipInitialization: false,
                ctorArgs: [voucher.address, voucher.address]
            });
            const tx = carbonController.tradeByTargetAmount(
                ZERO_ADDRESS,
                ZERO_ADDRESS,
                [{ strategyId: 1, amount: 1 }],
                1,
                1
            );
            await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
        });
    });
});
