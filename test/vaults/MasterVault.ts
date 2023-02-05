import Contracts, { CarbonController, IERC20, MasterVault } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { TokenData, TokenSymbol } from '../../utils/TokenData';
import { expectRole, expectRoles, Roles } from '../helpers/AccessControl';
import { createSystem, createToken, TokenWithAddress } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { transfer } from '../helpers/Utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('MasterVault', () => {
    shouldHaveGap('MasterVault');

    describe('construction', () => {
        let masterVault: MasterVault;
        let carbonController: CarbonController;

        beforeEach(async () => {
            ({ masterVault, carbonController } = await createSystem());
        });

        it('should revert when attempting to reinitialize', async () => {
            await expect(masterVault.initialize()).to.be.revertedWithError(
                'Initializable: contract is already initialized'
            );
        });

        it('should be properly initialized', async () => {
            expect(await masterVault.version()).to.equal(1);
            expect(await masterVault.isPayable()).to.be.true;

            await expectRoles(masterVault, Roles.Vault);

            await expectRole(masterVault, Roles.Vault.ROLE_ASSET_MANAGER, Roles.Upgradeable.ROLE_ADMIN, [
                carbonController.address
            ]);
        });
    });

    describe('asset management', () => {
        const amount = 1_000_000;

        let masterVault: MasterVault;

        let deployer: SignerWithAddress;
        let user: SignerWithAddress;

        let token: TokenWithAddress;

        const testWithdrawFunds = () => {
            it('should allow withdrawals', async () => {
                await expect(masterVault.connect(user).withdrawFunds(token.address, user.address, amount))
                    .to.emit(masterVault, 'FundsWithdrawn')
                    .withArgs(token.address, user.address, user.address, amount);
            });
        };

        const testWithdrawFundsRestricted = () => {
            it('should revert', async () => {
                await expect(
                    masterVault.connect(user).withdrawFunds(token.address, user.address, amount)
                ).to.revertedWithError('AccessDenied');
            });
        };

        before(async () => {
            [deployer, user] = await ethers.getSigners();
        });

        for (const symbol of [TokenSymbol.ETH, TokenSymbol.TKN]) {
            const tokenData = new TokenData(symbol);

            context(`withdrawing ${symbol}`, () => {
                beforeEach(async () => {
                    ({ masterVault } = await createSystem());

                    token = await createToken(tokenData);

                    await transfer(deployer, token, masterVault.address, amount);
                });

                context('with no special permissions', () => {
                    testWithdrawFundsRestricted();
                });

                context('with admin role', () => {
                    beforeEach(async () => {
                        await masterVault.grantRole(Roles.Upgradeable.ROLE_ADMIN, user.address);
                    });

                    testWithdrawFundsRestricted();
                });

                context('with asset manager role', () => {
                    beforeEach(async () => {
                        await masterVault.grantRole(Roles.Vault.ROLE_ASSET_MANAGER, user.address);
                    });

                    testWithdrawFunds();
                });
            });
        }
    });
});
