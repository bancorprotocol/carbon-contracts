import Contracts, {
    FeeBurner,
    MockBancorNetworkV3,
    TestBNT,
    TestCarbonController,
    TestERC20Burnable
} from '../../components/Contracts';
import { MAX_UINT256, PPM_RESOLUTION } from '../../utils/Constants';
import { Roles } from '../../utils/Roles';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../utils/TokenData';
import { toWei } from '../../utils/Types';
import { createBNT, createBurnableToken, createFeeBurner, createSystem, Tokens } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { setBalance, toAddress } from '../helpers/Utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('FeeBurner', () => {
    let deployer: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let feeBurner: FeeBurner;
    let carbonController: TestCarbonController;
    let bnt: TestBNT;
    let token0: TestERC20Burnable;
    let token1: TestERC20Burnable;
    let nonTradeableToken: TestERC20Burnable;
    let bancorNetworkV3: MockBancorNetworkV3;
    let tokens: Tokens = {};
    const MAX_SOURCE_AMOUNT = toWei(1_000_000);

    const ArbitrageRewardsDefaults = {
        percentagePPM: 100_000,
        maxAmount: toWei(100)
    };

    const ArbitrageRewardsChanged = {
        percentagePPM: 110_000,
        maxAmount: toWei(10)
    };

    shouldHaveGap('FeeBurner', '_rewards');

    before(async () => {
        [deployer, , nonAdmin] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ carbonController } = await createSystem());
        bnt = await createBNT();
        bancorNetworkV3 = await Contracts.MockBancorNetworkV3.deploy(toAddress(bnt), toWei(300), true);
        feeBurner = await createFeeBurner(bnt, carbonController, bancorNetworkV3);

        // grant fee manager role to fee burner
        await carbonController.connect(deployer).grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, feeBurner.address);

        tokens = {};
        for (const symbol of [TokenSymbol.ETH, TokenSymbol.TKN0, TokenSymbol.TKN1, TokenSymbol.TKN2]) {
            tokens[symbol] = await createBurnableToken(new TokenData(symbol));
        }

        token0 = tokens[TokenSymbol.TKN0];
        token1 = tokens[TokenSymbol.TKN1];
        nonTradeableToken = tokens[TokenSymbol.TKN2];

        // set up bancor network v3 tradeable tokens
        await bancorNetworkV3.setCollectionByPool(toAddress(bnt));
        await bancorNetworkV3.setCollectionByPool(toAddress(token0));
        await bancorNetworkV3.setCollectionByPool(toAddress(token1));
        await bancorNetworkV3.setCollectionByPool(NATIVE_TOKEN_ADDRESS);

        // transfer tokens to bancor network v3
        await bnt.transfer(toAddress(bancorNetworkV3), MAX_SOURCE_AMOUNT);
        await token0.transfer(toAddress(bancorNetworkV3), MAX_SOURCE_AMOUNT);
        await token1.transfer(toAddress(bancorNetworkV3), MAX_SOURCE_AMOUNT);
        await setBalance(toAddress(bancorNetworkV3), MAX_SOURCE_AMOUNT);

        // transfer tokens to carbon controller
        await bnt.transfer(toAddress(carbonController), MAX_SOURCE_AMOUNT);
        await token0.transfer(toAddress(carbonController), MAX_SOURCE_AMOUNT);
        await token1.transfer(toAddress(carbonController), MAX_SOURCE_AMOUNT);
        await nonTradeableToken.transfer(toAddress(carbonController), MAX_SOURCE_AMOUNT);
        await setBalance(toAddress(carbonController), MAX_SOURCE_AMOUNT);
    });

    describe('construction', () => {
        it('should revert when initializing with an invalid bnt contract', async () => {
            await expect(
                Contracts.FeeBurner.deploy(
                    ethers.constants.AddressZero,
                    toAddress(carbonController),
                    toAddress(bancorNetworkV3)
                )
            ).to.be.revertedWithError('InvalidAddress');
        });

        it('should revert when initializing with an invalid carbon controller contract', async () => {
            await expect(
                Contracts.FeeBurner.deploy(toAddress(bnt), ethers.constants.AddressZero, toAddress(bancorNetworkV3))
            ).to.be.revertedWithError('InvalidAddress');
        });

        it('should revert when initializing with an invalid carbon controller contract', async () => {
            await expect(
                Contracts.FeeBurner.deploy(toAddress(bnt), toAddress(carbonController), ethers.constants.AddressZero)
            ).to.be.revertedWithError('InvalidAddress');
        });

        it('should be initialized', async () => {
            expect(await feeBurner.version()).to.equal(1);
        });

        it('should revert when attempting to reinitialize', async () => {
            await expect(feeBurner.initialize()).to.be.revertedWithError(
                'Initializable: contract is already initialized'
            );
        });
    });

    describe('rewards', () => {
        it('should revert when a non-admin attempts to set the arbitrage rewards settings', async () => {
            await expect(feeBurner.connect(nonAdmin).setRewards(ArbitrageRewardsDefaults)).to.be.revertedWithError(
                'AccessDenied'
            );
        });

        it('should ignore setting to the same arbitrage rewards settings', async () => {
            await feeBurner.setRewards(ArbitrageRewardsDefaults);

            const res = await feeBurner.setRewards(ArbitrageRewardsDefaults);
            await expect(res).not.to.emit(feeBurner, 'RewardsUpdated');
        });

        it('should be able to set and update the arbitrage rewards settings', async () => {
            await feeBurner.setRewards(ArbitrageRewardsDefaults);

            const res = await feeBurner.rewards();
            expect(res.percentagePPM).to.equal(ArbitrageRewardsDefaults.percentagePPM);
            expect(res.maxAmount).to.equal(ArbitrageRewardsDefaults.maxAmount);

            const resChanged = await feeBurner.setRewards(ArbitrageRewardsChanged);
            await expect(resChanged).to.emit(feeBurner, 'RewardsUpdated');

            const resUpdated = await feeBurner.rewards();
            expect(resUpdated.percentagePPM).to.equal(ArbitrageRewardsChanged.percentagePPM);
            expect(resUpdated.maxAmount).to.equal(ArbitrageRewardsChanged.maxAmount);
        });

        describe('distribution and burn', () => {
            it('should distribute rewards to user and burn bnt with fee token input as BNT', async () => {
                // set accumulated fees
                const amount = toWei(50);
                await carbonController.testSetAccumulatedFees(bnt.address, amount);

                const rewards = await feeBurner.rewards();

                const balanceBefore = await bnt.balanceOf(deployer.address);
                const supplyBefore = await bnt.totalSupply();

                // we don't convert bnt, so we expect to get 10% of 50 BNT
                const expectedUserRewards = amount.mul(rewards.percentagePPM).div(PPM_RESOLUTION);
                const expectedBntBurnt = amount.sub(expectedUserRewards);

                await expect(feeBurner.execute([bnt.address]))
                    .to.emit(feeBurner, 'FeesBurnt')
                    .withArgs(deployer.address, expectedBntBurnt, expectedUserRewards);

                const balanceAfter = await bnt.balanceOf(deployer.address);
                const supplyAfter = await bnt.totalSupply();

                const bntGain = balanceAfter.sub(balanceBefore);
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(bntGain).to.be.eq(expectedUserRewards);
                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
            });

            it('should correctly distribute rewards to user and burn bnt', async () => {
                // set accumulated fees
                const token0Amount = toWei(50);
                const token1Amount = toWei(30);
                const token2Amount = toWei(10);
                await carbonController.testSetAccumulatedFees(token0.address, token0Amount);
                await carbonController.testSetAccumulatedFees(token1.address, token1Amount);
                await carbonController.testSetAccumulatedFees(NATIVE_TOKEN_ADDRESS, token2Amount);

                const rewards = await feeBurner.rewards();

                const balanceBefore = await bnt.balanceOf(deployer.address);
                const supplyBefore = await bnt.totalSupply();

                // in mock bancor network v3, each token swap adds 300e18 tokens to the output
                // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
                const swapGain = toWei(300).mul(3);
                const totalAmount = token0Amount.add(token1Amount).add(token2Amount).add(swapGain);

                const expectedUserRewards = totalAmount.mul(rewards.percentagePPM).div(PPM_RESOLUTION);

                const expectedBntBurnt = totalAmount.sub(expectedUserRewards);

                await expect(feeBurner.execute([token0.address, token1.address, NATIVE_TOKEN_ADDRESS]))
                    .to.emit(feeBurner, 'FeesBurnt')
                    .withArgs(deployer.address, expectedBntBurnt, expectedUserRewards);

                const balanceAfter = await bnt.balanceOf(deployer.address);
                const supplyAfter = await bnt.totalSupply();

                const bntGain = balanceAfter.sub(balanceBefore);
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
                expect(bntGain).to.be.eq(expectedUserRewards);
            });

            it('should correctly distribute rewards to user and burn bnt if rewards exceed max amount', async () => {
                // set accumulated fees
                const token0Amount = toWei(50);
                const token1Amount = toWei(30);
                const token2Amount = toWei(10);
                await carbonController.testSetAccumulatedFees(token0.address, token0Amount);
                await carbonController.testSetAccumulatedFees(token1.address, token1Amount);
                await carbonController.testSetAccumulatedFees(NATIVE_TOKEN_ADDRESS, token2Amount);

                const balanceBefore = await bnt.balanceOf(deployer.address);
                const supplyBefore = await bnt.totalSupply();

                await feeBurner.setRewards(ArbitrageRewardsChanged);
                const rewards = await feeBurner.rewards();

                // in mock bancor network v3, each token swap adds 300e18 tokens to the output
                // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
                const swapGain = toWei(300).mul(3);
                const totalAmount = token0Amount.add(token1Amount).add(token2Amount).add(swapGain);

                let expectedUserRewards = totalAmount.mul(rewards.percentagePPM).div(PPM_RESOLUTION);

                // check we have exceeded the max amount
                expect(expectedUserRewards).to.be.gt(rewards.maxAmount);
                // set the expected rewards to the max amount
                expectedUserRewards = rewards.maxAmount;

                const expectedBntBurnt = totalAmount.sub(expectedUserRewards);

                await expect(feeBurner.execute([token0.address, token1.address, NATIVE_TOKEN_ADDRESS]))
                    .to.emit(feeBurner, 'FeesBurnt')
                    .withArgs(deployer.address, expectedBntBurnt, expectedUserRewards);

                const balanceAfter = await bnt.balanceOf(deployer.address);
                const supplyAfter = await bnt.totalSupply();

                // user rewards are sent to user address, increasing his bnt balance
                const bntGain = balanceAfter.sub(balanceBefore);

                // bnt is burnt by sending it to BNT's address
                // total supply of BNT gets decreased
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
                expect(bntGain).to.be.eq(expectedUserRewards);
            });
        });
    });

    describe('burn function', () => {
        it('should withdraw fees on fee burn', async () => {
            // set accumulated fees
            const amounts = [toWei(50), toWei(80), toWei(1)];
            const tokens = [bnt.address, token0.address, NATIVE_TOKEN_ADDRESS];

            for (let i = 0; i < tokens.length; ++i) {
                await carbonController.testSetAccumulatedFees(tokens[i], amounts[i]);

                await expect(feeBurner.execute([tokens[i]]))
                    .to.emit(carbonController, 'FeesWithdrawn')
                    .withArgs(tokens[i], feeBurner.address, amounts[i], feeBurner.address);
            }
        });

        it('should emit event on successful burn', async () => {
            // set accumulated fees
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);

            // we don't convert bnt, so we expect to get 10% of 50 BNT
            const rewardAmount = amount.mul(ArbitrageRewardsDefaults.percentagePPM).div(PPM_RESOLUTION);

            const burnAmount = amount.sub(rewardAmount);

            await expect(feeBurner.execute([bnt.address]))
                .to.emit(feeBurner, 'FeesBurnt')
                .withArgs(deployer.address, burnAmount, rewardAmount);
        });

        it('should correctly increase total burnt amount on burn', async () => {
            // set accumulated fees
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);

            // we don't convert bnt, so we expect to get 10% of 50 BNT
            const rewardAmount = amount.mul(ArbitrageRewardsDefaults.percentagePPM).div(PPM_RESOLUTION);

            const burnAmount = amount.sub(rewardAmount);

            const totalBurntBefore = await feeBurner.totalBurnt();

            await feeBurner.execute([bnt.address]);

            const totalBurntAfter = await feeBurner.totalBurnt();
            expect(totalBurntBefore.add(burnAmount)).to.be.equal(totalBurntAfter);
        });

        it("should skip tokens which don't have accumulated fees", async () => {
            // set accumulated fees for token0 and bnt
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(token0.address, amount);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);
            // we don't convert bnt, so we expect to get 10% of 50 BNT
            const totalAmount = amount.add(amount).add(toWei(300));
            const rewardAmount = totalAmount.mul(ArbitrageRewardsDefaults.percentagePPM).div(PPM_RESOLUTION);

            const burnAmount = totalAmount.sub(rewardAmount);

            // burn token0, bnt and token1
            // token1 has 0 accumulated fees
            await expect(feeBurner.execute([token0.address, bnt.address, token1.address]))
                .to.emit(feeBurner, 'FeesBurnt')
                .withArgs(deployer.address, burnAmount, rewardAmount);
        });

        it('should approve tokens to bancor network v3 if allowance is less than the fee swap amount', async () => {
            // set accumulated fees
            const token0Amount = toWei(50);
            const token1Amount = toWei(30);
            await carbonController.testSetAccumulatedFees(token0.address, token0Amount);
            await carbonController.testSetAccumulatedFees(token1.address, token1Amount);

            const tokens = [token0.address, token1.address];

            for (const token of tokens) {
                // expect to approve MAX_UINT256
                const approveAmount = MAX_UINT256;
                const approveExchange = bancorNetworkV3.address;
                const contract = await Contracts.TestERC20Token.attach(token);
                const allowance = await contract.allowance(feeBurner.address, approveExchange);
                if (allowance.eq(0)) {
                    await expect(feeBurner.execute([token]))
                        .to.emit(contract, 'Approval')
                        .withArgs(feeBurner.address, approveExchange, approveAmount);
                }
            }

            // set accumulated fees
            await carbonController.testSetAccumulatedFees(token0.address, token0Amount);
            await carbonController.testSetAccumulatedFees(token1.address, token1Amount);

            // expect further burns not to emit approve, since the swap amount < MAX_UINT256
            for (const token of tokens) {
                // expect to approve MAX_UINT256
                const approveAmount = MAX_UINT256;
                const approveExchange = bancorNetworkV3.address;
                const contract = await Contracts.TestERC20Token.attach(token);
                await expect(feeBurner.execute([token]))
                    .not.to.emit(contract, 'Approval')
                    .withArgs(feeBurner.address, approveExchange, approveAmount);
            }
        });

        it('should revert if any of the tokens sent is not tradeable on Bancor Network V3', async () => {
            // set accumulated fees for token0
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(nonTradeableToken.address, amount);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);

            // burn nonTradeableToken and bnt
            await expect(feeBurner.execute([bnt.address, nonTradeableToken.address])).to.be.revertedWithError(
                'InvalidToken'
            );
        });
    });
});
