import Contracts, {
    CarbonVortex,
    MockBancorNetworkV3,
    TestBNT,
    TestCarbonController,
    TestERC20Burnable
} from '../../components/Contracts';
import { MAX_UINT256, PPM_RESOLUTION, ZERO_ADDRESS } from '../../utils/Constants';
import { Roles } from '../../utils/Roles';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../utils/TokenData';
import { toWei } from '../../utils/Types';
import { createBNT, createBurnableToken, createCarbonVortex, createSystem, Tokens } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { setBalance, toAddress } from '../helpers/Utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('CarbonVortex', () => {
    let deployer: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let carbonVortex: CarbonVortex;
    let carbonController: TestCarbonController;
    let bnt: TestBNT;
    let token0: TestERC20Burnable;
    let token1: TestERC20Burnable;
    let nonTradeableToken: TestERC20Burnable;
    let bancorNetworkV3: MockBancorNetworkV3;
    let tokens: Tokens = {};
    const MAX_SOURCE_AMOUNT = toWei(1_000_000);

    const RewardsPPMDefault = 100_000;

    const RewardsPPMChanged = 110_000;

    shouldHaveGap('CarbonVortex', '_totalBurned');

    before(async () => {
        [deployer, , nonAdmin] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ carbonController } = await createSystem());
        bnt = await createBNT();
        bancorNetworkV3 = await Contracts.MockBancorNetworkV3.deploy(toAddress(bnt), toWei(300), true);
        carbonVortex = await createCarbonVortex(bnt, carbonController, bancorNetworkV3);

        // grant fee manager role to carbon vortex
        await carbonController
            .connect(deployer)
            .grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, carbonVortex.address);

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
                Contracts.CarbonVortex.deploy(
                    ethers.constants.AddressZero,
                    toAddress(carbonController),
                    toAddress(bancorNetworkV3)
                )
            ).to.be.revertedWithError('InvalidAddress');
        });

        it('should revert when initializing with an invalid carbon controller contract', async () => {
            await expect(
                Contracts.CarbonVortex.deploy(toAddress(bnt), ethers.constants.AddressZero, toAddress(bancorNetworkV3))
            ).to.be.revertedWithError('InvalidAddress');
        });

        it('should revert when initializing with an invalid carbon controller contract', async () => {
            await expect(
                Contracts.CarbonVortex.deploy(toAddress(bnt), toAddress(carbonController), ethers.constants.AddressZero)
            ).to.be.revertedWithError('InvalidAddress');
        });

        it('should be initialized', async () => {
            expect(await carbonVortex.version()).to.equal(2);
        });

        it('should revert when attempting to reinitialize', async () => {
            await expect(carbonVortex.initialize()).to.be.revertedWithError(
                'Initializable: contract is already initialized'
            );
        });
    });

    describe('rewards', () => {
        it('should revert when a non-admin attempts to set the arbitrage rewards settings', async () => {
            await expect(carbonVortex.connect(nonAdmin).setRewardsPPM(RewardsPPMDefault)).to.be.revertedWithError(
                'AccessDenied'
            );
        });

        it('should revert setting the arbitrage rewards with an invalid fee', async () => {
            const invalidFee = PPM_RESOLUTION + 1;
            await expect(carbonVortex.setRewardsPPM(invalidFee)).to.be.revertedWithError('InvalidFee');
        });

        it('should ignore setting to the same arbitrage rewards settings', async () => {
            await carbonVortex.setRewardsPPM(RewardsPPMDefault);

            const res = await carbonVortex.setRewardsPPM(RewardsPPMDefault);
            await expect(res).not.to.emit(carbonVortex, 'RewardsUpdated');
        });

        it('should be able to set and update the arbitrage rewards settings', async () => {
            await carbonVortex.setRewardsPPM(RewardsPPMDefault);

            const res = await carbonVortex.rewardsPPM();
            expect(res).to.equal(RewardsPPMDefault);

            const resChanged = await carbonVortex.setRewardsPPM(RewardsPPMChanged);
            await expect(resChanged).to.emit(carbonVortex, 'RewardsUpdated');

            const resUpdated = await carbonVortex.rewardsPPM();
            expect(resUpdated).to.equal(RewardsPPMChanged);
        });

        describe('distribution and burn', () => {
            it('should distribute rewards to user and burn bnt with fee token input as BNT', async () => {
                // set accumulated fees
                const amount = toWei(50);
                await carbonController.testSetAccumulatedFees(bnt.address, amount);

                const rewards = await carbonVortex.rewardsPPM();

                const balanceBefore = await bnt.balanceOf(deployer.address);
                const supplyBefore = await bnt.totalSupply();

                // we don't convert bnt, so we expect to get 10% of 50 BNT
                const expectedUserRewards = [amount.mul(rewards).div(PPM_RESOLUTION)];
                const expectedBntBurnt = amount.sub(expectedUserRewards[0]);
                const tokens = [bnt.address];

                await expect(carbonVortex.execute(tokens))
                    .to.emit(carbonVortex, 'FeesBurnt')
                    .withArgs(deployer.address, tokens, expectedUserRewards, expectedBntBurnt);

                const balanceAfter = await bnt.balanceOf(deployer.address);
                const supplyAfter = await bnt.totalSupply();

                const bntGain = balanceAfter.sub(balanceBefore);
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(bntGain).to.be.eq(expectedUserRewards[0]);
                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
            });

            it('should correctly distribute rewards to user and burn bnt if fees have accumulated', async () => {
                // set accumulated fees
                const tokenAmounts = [toWei(50), toWei(30), toWei(10)];
                await carbonController.testSetAccumulatedFees(token0.address, tokenAmounts[0]);
                await carbonController.testSetAccumulatedFees(token1.address, tokenAmounts[1]);
                await carbonController.testSetAccumulatedFees(NATIVE_TOKEN_ADDRESS, tokenAmounts[2]);

                const rewards = await carbonVortex.rewardsPPM();

                const balancesBefore = [];
                balancesBefore[0] = await token0.balanceOf(deployer.address);
                balancesBefore[1] = await token1.balanceOf(deployer.address);
                balancesBefore[2] = await deployer.getBalance();

                const supplyBefore = await bnt.totalSupply();

                // in mock bancor network v3, each token swap adds 300e18 tokens to the output
                // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
                const swapGain = toWei(300).mul(3);

                const expectedUserRewards = [];
                const expectedSwapAmounts = [];

                for (let i = 0; i < 3; ++i) {
                    const reward = tokenAmounts[i].mul(rewards).div(PPM_RESOLUTION);
                    expectedUserRewards.push(reward);
                    expectedSwapAmounts.push(tokenAmounts[i].sub(expectedUserRewards[i]));
                }

                const expectedBntBurnt = expectedSwapAmounts[0]
                    .add(expectedSwapAmounts[1])
                    .add(expectedSwapAmounts[2])
                    .add(swapGain);

                const tokens = [token0.address, token1.address, NATIVE_TOKEN_ADDRESS];

                const tx = await carbonVortex.execute(tokens);
                await expect(tx)
                    .to.emit(carbonVortex, 'FeesBurnt')
                    .withArgs(deployer.address, tokens, expectedUserRewards, expectedBntBurnt);

                // account for gas used
                const receipt = await tx.wait();
                const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

                const balancesAfter = [];
                balancesAfter[0] = await token0.balanceOf(deployer.address);
                balancesAfter[1] = await token1.balanceOf(deployer.address);
                balancesAfter[2] = await deployer.getBalance();
                const supplyAfter = await bnt.totalSupply();

                const balanceGains = [];
                balanceGains[0] = balancesAfter[0].sub(balancesBefore[0]);
                balanceGains[1] = balancesAfter[1].sub(balancesBefore[1]);
                balanceGains[2] = balancesAfter[2].sub(balancesBefore[2]).add(gasUsed);
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
                expect(balanceGains[0]).to.be.eq(expectedUserRewards[0]);
                expect(balanceGains[1]).to.be.eq(expectedUserRewards[1]);
                expect(balanceGains[2]).to.be.eq(expectedUserRewards[2]);
            });

            it('should correctly distribute rewards to user and burn bnt if contract has token balance', async () => {
                // transfer tokens to carbon vortex
                const tokenAmounts = [toWei(50), toWei(30), toWei(10)];
                await token0.transfer(carbonVortex.address, tokenAmounts[0]);
                await token1.transfer(carbonVortex.address, tokenAmounts[1]);
                await deployer.sendTransaction({ to: carbonVortex.address, value: tokenAmounts[2] });

                const rewards = await carbonVortex.rewardsPPM();

                const balancesBefore = [];
                balancesBefore[0] = await token0.balanceOf(deployer.address);
                balancesBefore[1] = await token1.balanceOf(deployer.address);
                balancesBefore[2] = await deployer.getBalance();

                const supplyBefore = await bnt.totalSupply();

                // in mock bancor network v3, each token swap adds 300e18 tokens to the output
                // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
                const swapGain = toWei(300).mul(3);

                const expectedUserRewards = [];
                const expectedSwapAmounts = [];

                for (let i = 0; i < 3; ++i) {
                    const reward = tokenAmounts[i].mul(rewards).div(PPM_RESOLUTION);
                    expectedUserRewards.push(reward);
                    expectedSwapAmounts.push(tokenAmounts[i].sub(expectedUserRewards[i]));
                }

                const expectedBntBurnt = expectedSwapAmounts[0]
                    .add(expectedSwapAmounts[1])
                    .add(expectedSwapAmounts[2])
                    .add(swapGain);

                const tokens = [token0.address, token1.address, NATIVE_TOKEN_ADDRESS];

                const tx = await carbonVortex.execute(tokens);
                await expect(tx)
                    .to.emit(carbonVortex, 'FeesBurnt')
                    .withArgs(deployer.address, tokens, expectedUserRewards, expectedBntBurnt);

                // account for gas used
                const receipt = await tx.wait();
                const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

                const balancesAfter = [];
                balancesAfter[0] = await token0.balanceOf(deployer.address);
                balancesAfter[1] = await token1.balanceOf(deployer.address);
                balancesAfter[2] = await deployer.getBalance();
                const supplyAfter = await bnt.totalSupply();

                const balanceGains = [];
                balanceGains[0] = balancesAfter[0].sub(balancesBefore[0]);
                balanceGains[1] = balancesAfter[1].sub(balancesBefore[1]);
                balanceGains[2] = balancesAfter[2].sub(balancesBefore[2]).add(gasUsed);
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
                expect(balanceGains[0]).to.be.eq(expectedUserRewards[0]);
                expect(balanceGains[1]).to.be.eq(expectedUserRewards[1]);
                expect(balanceGains[2]).to.be.eq(expectedUserRewards[2]);
            });

            it('should correctly distribute rewards to user and burn bnt for token balance and accumulated fees', async () => {
                // transfer tokens to vortex
                const tokenAmounts = [toWei(100), toWei(60), toWei(20)];
                await token0.transfer(carbonVortex.address, tokenAmounts[0].div(2));
                await token1.transfer(carbonVortex.address, tokenAmounts[1].div(2));
                await deployer.sendTransaction({ to: carbonVortex.address, value: tokenAmounts[2].div(2) });
                // set accumulated fees
                await carbonController.testSetAccumulatedFees(token0.address, tokenAmounts[0].div(2));
                await carbonController.testSetAccumulatedFees(token1.address, tokenAmounts[1].div(2));
                await carbonController.testSetAccumulatedFees(NATIVE_TOKEN_ADDRESS, tokenAmounts[2].div(2));

                const rewards = await carbonVortex.rewardsPPM();

                const balancesBefore = [];
                balancesBefore[0] = await token0.balanceOf(deployer.address);
                balancesBefore[1] = await token1.balanceOf(deployer.address);
                balancesBefore[2] = await deployer.getBalance();

                const supplyBefore = await bnt.totalSupply();

                // in mock bancor network v3, each token swap adds 300e18 tokens to the output
                // we swap tokens to BNT, so the end gain is token count * 300 (without counting BNT)
                const swapGain = toWei(300).mul(3);

                const expectedUserRewards = [];
                const expectedSwapAmounts = [];

                for (let i = 0; i < 3; ++i) {
                    const reward = tokenAmounts[i].mul(rewards).div(PPM_RESOLUTION);
                    expectedUserRewards.push(reward);
                    expectedSwapAmounts.push(tokenAmounts[i].sub(expectedUserRewards[i]));
                }

                const expectedBntBurnt = expectedSwapAmounts[0]
                    .add(expectedSwapAmounts[1])
                    .add(expectedSwapAmounts[2])
                    .add(swapGain);

                const tokens = [token0.address, token1.address, NATIVE_TOKEN_ADDRESS];

                const tx = await carbonVortex.execute(tokens);
                await expect(tx)
                    .to.emit(carbonVortex, 'FeesBurnt')
                    .withArgs(deployer.address, tokens, expectedUserRewards, expectedBntBurnt);

                // account for gas used
                const receipt = await tx.wait();
                const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

                const balancesAfter = [];
                balancesAfter[0] = await token0.balanceOf(deployer.address);
                balancesAfter[1] = await token1.balanceOf(deployer.address);
                balancesAfter[2] = await deployer.getBalance();
                const supplyAfter = await bnt.totalSupply();

                const balanceGains = [];
                balanceGains[0] = balancesAfter[0].sub(balancesBefore[0]);
                balanceGains[1] = balancesAfter[1].sub(balancesBefore[1]);
                balanceGains[2] = balancesAfter[2].sub(balancesBefore[2]).add(gasUsed);
                const supplyBurnt = supplyBefore.sub(supplyAfter);

                expect(supplyBurnt).to.be.eq(expectedBntBurnt);
                expect(balanceGains[0]).to.be.eq(expectedUserRewards[0]);
                expect(balanceGains[1]).to.be.eq(expectedUserRewards[1]);
                expect(balanceGains[2]).to.be.eq(expectedUserRewards[2]);
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

                await expect(carbonVortex.execute([tokens[i]]))
                    .to.emit(carbonController, 'FeesWithdrawn')
                    .withArgs(tokens[i], carbonVortex.address, amounts[i], carbonVortex.address);
            }
        });

        it('should emit event on successful burn', async () => {
            // set accumulated fees
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);

            const tokens = [bnt.address];
            // we don't convert bnt, so we expect to get 10% of 50 BNT
            const rewardAmounts = [amount.mul(RewardsPPMDefault).div(PPM_RESOLUTION)];

            const burnAmount = amount.sub(rewardAmounts[0]);

            await expect(carbonVortex.execute([bnt.address]))
                .to.emit(carbonVortex, 'FeesBurnt')
                .withArgs(deployer.address, tokens, rewardAmounts, burnAmount);
        });

        it('should correctly increase total burned amount on burn', async () => {
            // set accumulated fees
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);

            // we don't convert bnt, so we expect to get 10% of 50 BNT
            const rewardAmount = amount.mul(RewardsPPMDefault).div(PPM_RESOLUTION);

            const burnAmount = amount.sub(rewardAmount);

            const totalBurnedBefore = await carbonVortex.totalBurned();

            await carbonVortex.execute([bnt.address]);

            const totalBurnedAfter = await carbonVortex.totalBurned();
            expect(totalBurnedBefore.add(burnAmount)).to.be.equal(totalBurnedAfter);
        });

        it('should correctly update available fees on burn', async () => {
            // expect fee amount to be 0 at the beginning
            const feeAmountBefore = await carbonVortex.availableFees(bnt.address);
            expect(feeAmountBefore).to.be.eq(0);

            // set accumulated fees
            const feeAmounts = [toWei(50), toWei(30)];
            await carbonController.testSetAccumulatedFees(bnt.address, feeAmounts[0]);
            // transfer tokens to contract
            await bnt.transfer(carbonVortex.address, feeAmounts[1]);

            const expectedFeeAmount = feeAmounts[0].add(feeAmounts[1]);
            const actualFeeAmount = await carbonVortex.availableFees(bnt.address);

            expect(expectedFeeAmount).to.be.eq(actualFeeAmount);

            await carbonVortex.execute([bnt.address]);

            // expect fee amount to be 0 after
            const feeAmountAfter = await carbonVortex.availableFees(bnt.address);
            expect(feeAmountAfter).to.be.eq(0);
        });

        it("should skip tokens which don't have accumulated fees", async () => {
            // set accumulated fees for token0 and bnt
            const fees = [toWei(50), toWei(30), toWei(0)];
            await carbonController.testSetAccumulatedFees(token0.address, fees[0]);
            await carbonController.testSetAccumulatedFees(bnt.address, fees[1]);
            await carbonController.testSetAccumulatedFees(token1.address, fees[2]);

            const rewards = await carbonVortex.rewardsPPM();

            const tokens = [token0.address, bnt.address, token1.address];
            // we don't convert bnt, so we expect to get 10% of 50 BNT
            const swapGain = toWei(300);
            const rewardAmounts = [];
            const swapAmounts = [];
            for (let i = 0; i < 3; ++i) {
                rewardAmounts[i] = fees[i].mul(rewards).div(PPM_RESOLUTION);
                swapAmounts[i] = fees[i].sub(rewardAmounts[i]);
            }

            const burnAmount = swapAmounts[0].add(swapAmounts[1]).add(swapGain);

            // burn token0, bnt and token1
            // token1 has 0 accumulated fees
            await expect(carbonVortex.execute(tokens))
                .to.emit(carbonVortex, 'FeesBurnt')
                .withArgs(deployer.address, tokens, rewardAmounts, burnAmount);
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
                const allowance = await contract.allowance(carbonVortex.address, approveExchange);
                if (allowance.eq(0)) {
                    await expect(carbonVortex.execute([token]))
                        .to.emit(contract, 'Approval')
                        .withArgs(carbonVortex.address, approveExchange, approveAmount);
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
                await expect(carbonVortex.execute([token]))
                    .not.to.emit(contract, 'Approval')
                    .withArgs(carbonVortex.address, approveExchange, approveAmount);
            }
        });

        it('should revert if any of the tokens sent is not tradeable on Bancor Network V3', async () => {
            // set accumulated fees for token0
            const amount = toWei(50);
            await carbonController.testSetAccumulatedFees(nonTradeableToken.address, amount);
            await carbonController.testSetAccumulatedFees(bnt.address, amount);

            // burn nonTradeableToken and bnt
            await expect(carbonVortex.execute([bnt.address, nonTradeableToken.address])).to.be.revertedWithError(
                'InvalidToken'
            );
        });

        it('should revert if any of the tokens sent has duplicates', async () => {
            await expect(carbonVortex.execute([bnt.address, token0.address, bnt.address])).to.be.revertedWithError(
                'DuplicateToken'
            );
        });

        it("should revert if any of the tokens sent doesn't exist", async () => {
            await expect(carbonVortex.execute([bnt.address, ZERO_ADDRESS])).to.be.revertedWithError('InvalidToken');
        });

        it('should revert if no tokens are sent', async () => {
            await expect(carbonVortex.execute([])).to.be.revertedWithError('InvalidTokenLength');
        });
    });
});
