import { expectRoleMembers, Roles } from '../../test/helpers/AccessControl';
import { createBurnableToken, Tokens } from '../../test/helpers/Factory';
import { shouldHaveGap } from '../../test/helpers/Proxy';
import { latest } from '../../test/helpers/Time';
import {
    CreateStrategyParams,
    generateStrategyId,
    generateTestOrder,
    mulDivC,
    mulDivF,
    setConstraint,
    TestOrder,
    toFixed,
    TradeParams,
    TradeTestReturnValues,
    UpdateStrategyParams
} from '../../test/helpers/Trading';
import { getBalance, transfer } from '../../test/helpers/Utils';
import { decodeOrder, encodeOrder } from '../../test/utility/carbon-sdk';
import { FactoryOptions, testCaseFactory, TestStrategy } from '../../test/utility/testDataFactory';
import { CarbonController, CarbonVortex, Voucher } from '../../typechain-types';
import { StrategyStruct } from '../../typechain-types/contracts/carbon/CarbonController';
import {
    DEFAULT_TRADING_FEE_PPM,
    PPM_RESOLUTION,
    STRATEGY_UPDATE_REASON_TRADE,
    ZERO_ADDRESS
} from '../../utils/Constants';
import { DeployedContracts, fundAccount, getNamedSigners, isMainnet, runPendingDeployments } from '../../utils/Deploy';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../utils/TokenData';
import { toWei } from '../../utils/Types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumber, BigNumberish } from 'ethers';
import { ethers, getNamedAccounts } from 'hardhat';

(isMainnet() ? describe : describe.skip)('network', async () => {
    let carbonController: CarbonController;
    let voucher: Voucher;
    let carbonVortex: CarbonVortex;

    let daoMultisig: SignerWithAddress;

    shouldHaveGap('CarbonController');
    shouldHaveGap('Pairs', '_lastPairId');
    shouldHaveGap('Strategies', '_strategyCounter');
    shouldHaveGap('Voucher', '_useGlobalURI');
    shouldHaveGap('CarbonVortex', '_totalBurned');

    before(async () => {
        ({ daoMultisig } = await getNamedSigners());
    });

    beforeEach(async () => {
        await runPendingDeployments();

        carbonController = await DeployedContracts.CarbonController.deployed();
        voucher = await DeployedContracts.Voucher.deployed();
        carbonVortex = await DeployedContracts.CarbonVortex.deployed();
    });

    describe('roles', () => {
        it('should have the correct set of roles', async () => {
            // expect dao multisig to be admin
            await expectRoleMembers(carbonController, Roles.Upgradeable.ROLE_ADMIN, [daoMultisig.address]);
            await expectRoleMembers(voucher, Roles.Upgradeable.ROLE_ADMIN, [daoMultisig.address]);
            await expectRoleMembers(carbonVortex, Roles.Upgradeable.ROLE_ADMIN, [daoMultisig.address]);

            // expect fee burner to have fee manager role in Carbon
            await expectRoleMembers(carbonController, Roles.CarbonController.ROLE_FEES_MANAGER, [carbonVortex.address]);

            // expect carbonController to have minter role in voucher
            await expectRoleMembers(voucher, Roles.Voucher.ROLE_MINTER, [carbonController.address]);
        });
    });

    describe('trading', () => {
        let deployer: SignerWithAddress;
        let marketMaker: SignerWithAddress;
        let trader: SignerWithAddress;
        let bntWhale: SignerWithAddress;
        let usdcWhale: SignerWithAddress;
        let daiWhale: SignerWithAddress;
        const tokens: Tokens = {};

        before(async () => {
            const { bnt, usdc, dai } = await getNamedAccounts();
            ({ deployer, bntWhale, usdcWhale, daiWhale } = await getNamedSigners());
            [marketMaker, trader] = await ethers.getSigners();
            await fundAccount(deployer, toWei(50000));
            await fundAccount(bntWhale);
            await fundAccount(marketMaker);
            await fundAccount(trader);

            tokens[TokenSymbol.BNT] = await ethers.getContractAt('TestERC20Burnable', bnt);
            tokens[TokenSymbol.DAI] = await ethers.getContractAt('TestERC20Burnable', dai);
            tokens[TokenSymbol.USDC] = await ethers.getContractAt('TestERC20Burnable', usdc);
            tokens[TokenSymbol.ETH] = await createBurnableToken(new TokenData(TokenSymbol.ETH));

            // fund deployer
            await transfer(bntWhale, tokens[TokenSymbol.BNT], deployer.address, toWei(1_000_000));
            await transfer(daiWhale, tokens[TokenSymbol.DAI], deployer.address, toWei(1_000_000));
            await transfer(usdcWhale, tokens[TokenSymbol.USDC], deployer.address, toWei(10_000_000, 6));
        });

        describe('strategy creation and update is correct', async () => {
            const permutations: FactoryOptions[] = [
                { sourceSymbol: TokenSymbol.BNT, targetSymbol: TokenSymbol.DAI, byTargetAmount: false },
                { sourceSymbol: TokenSymbol.BNT, targetSymbol: TokenSymbol.DAI, byTargetAmount: true },
                { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.USDC, byTargetAmount: false },
                { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.DAI, byTargetAmount: true },
                { sourceSymbol: TokenSymbol.DAI, targetSymbol: TokenSymbol.ETH, byTargetAmount: true },
                { sourceSymbol: TokenSymbol.USDC, targetSymbol: TokenSymbol.ETH, byTargetAmount: true }
            ];
            for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
                it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                    const testCase = testCaseFactory({
                        sourceSymbol,
                        targetSymbol,
                        byTargetAmount
                    });

                    // create strategies
                    const strategyIds = await createStrategies(testCase.strategies);
                    // set correct strategy ids for the trade actions
                    for (let i = 0; i < testCase.tradeActions.length; ++i) {
                        testCase.tradeActions[i].strategyId = strategyIds[i];
                    }

                    // fund user for a trade
                    const { sourceAmount, targetAmount } = testCase;
                    await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                    // get token fees before trade
                    const sourceTokenFeesBefore = await carbonController.accumulatedFees(
                        tokens[testCase.sourceSymbol].address
                    );
                    const targetTokenFeesBefore = await carbonController.accumulatedFees(
                        tokens[testCase.targetSymbol].address
                    );

                    // perform trade
                    const { receipt } = await trade({
                        sourceAmount,
                        targetAmount,
                        tradeActions: testCase.tradeActions,
                        sourceSymbol: testCase.sourceSymbol,
                        targetSymbol: testCase.targetSymbol,
                        byTargetAmount: testCase.byTargetAmount
                    });

                    // get token fees after trade
                    const sourceTokenFeesAfter = await carbonController.accumulatedFees(
                        tokens[testCase.sourceSymbol].address
                    );
                    const targetTokenFeesAfter = await carbonController.accumulatedFees(
                        tokens[testCase.targetSymbol].address
                    );
                    const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);

                    // check token fees are correct
                    if (byTargetAmount) {
                        expect(sourceTokenFeesAfter).to.eq(sourceTokenFeesBefore.add(tradingFeeAmount));
                    } else {
                        expect(targetTokenFeesAfter).to.eq(targetTokenFeesBefore.add(tradingFeeAmount));
                    }

                    // --- check StrategyUpdated and TokensTraded events are emitted ---
                    // assert
                    if (!receipt || !receipt.events) {
                        expect.fail('No events emitted');
                    }
                    const event = receipt.events[receipt.events.length - 1];
                    if (!event.args) {
                        expect.fail('event emitted without args');
                    }
                    // prepare variables for assertions
                    const { expectedSourceAmount, expectedTargetAmount } = expectedSourceTargetAmounts(
                        byTargetAmount,
                        sourceAmount,
                        targetAmount,
                        tradingFeeAmount
                    );

                    // Check proper TokensTraded event emit
                    const sourceToken = tokens[sourceSymbol];
                    const targetToken = tokens[targetSymbol];
                    const eventArgs = event.args;
                    expect(eventArgs.sourceToken).to.eq(sourceToken.address);
                    expect(eventArgs.targetToken).to.eq(targetToken.address);
                    expect(eventArgs.sourceAmount).to.eq(expectedSourceAmount);
                    expect(eventArgs.targetAmount).to.eq(expectedTargetAmount);
                    expect(eventArgs.tradingFeeAmount).to.eq(tradingFeeAmount);
                    expect(eventArgs.byTargetAmount).to.eq(byTargetAmount);
                    expect(event.event).to.eq('TokensTraded');

                    const tradeActionsAmount = testCase.tradeActions.length;
                    for (let i = 0; i < tradeActionsAmount; i++) {
                        const strategy = testCase.strategies[i];
                        const event = receipt.events[i];
                        if (!event.args) {
                            expect.fail('Event contains no args');
                        }

                        // check proper strategyUpdated event emit
                        for (let x = 0; x < 2; x++) {
                            const expectedOrder = strategy.orders[x].expected;
                            const emittedOrder = decodeOrder(event.args[`order${x}`]);
                            expect(emittedOrder.liquidity.toFixed()).to.eq(expectedOrder.liquidity);
                            expect(toFixed(emittedOrder.lowestRate)).to.eq(expectedOrder.lowestRate);
                            expect(toFixed(emittedOrder.highestRate)).to.eq(expectedOrder.highestRate);
                            expect(toFixed(emittedOrder.marginalRate)).to.eq(expectedOrder.marginalRate);
                            expect(event.args[`token${x}`]).to.eq(tokens[strategy.orders[x].token].address);
                            expect(event.args.reason).to.eq(STRATEGY_UPDATE_REASON_TRADE);
                            expect(event.event).to.eq('StrategyUpdated');
                        }
                    }

                    // --- Check orders are stored correctly ---
                    // fetch updated data from the chain
                    const token0 = tokens[testCase.sourceSymbol];
                    const token1 = tokens[testCase.targetSymbol];
                    const strategies = await carbonController.strategiesByPair(token0.address, token1.address, 0, 0);

                    // assertions
                    strategies.forEach((strategy, i) => {
                        // check only strategies we've created in the test
                        if (strategyIds.includes(strategy.id)) {
                            strategy.orders.forEach((order, x) => {
                                const { y, z, A, B } = order;
                                const encodedOrder = decodeOrder({ y, z, A, B });
                                const expectedOrder = testCase.strategies[i].orders[x].expected;

                                expect(encodedOrder.liquidity.toFixed()).to.eq(expectedOrder.liquidity);
                                expect(toFixed(encodedOrder.lowestRate)).to.eq(expectedOrder.lowestRate);
                                expect(toFixed(encodedOrder.highestRate)).to.eq(expectedOrder.highestRate);
                                expect(toFixed(encodedOrder.marginalRate)).to.eq(expectedOrder.marginalRate);
                            });
                        }
                    });
                });
            }
        });

        /**
         * calculates and transfers to the trader the full amount required for a trade.
         */
        const fundTrader = async (
            sourceAmount: BigNumberish,
            targetAmount: BigNumberish,
            byTargetAmount: boolean,
            sourceSymbol: string
        ) => {
            const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);
            const { expectedSourceAmount } = expectedSourceTargetAmounts(
                byTargetAmount,
                sourceAmount,
                targetAmount,
                tradingFeeAmount
            );
            await transfer(deployer, tokens[sourceSymbol], trader, expectedSourceAmount);
        };

        /**
         * returns the tradingFeeAmount expected for the specified arguments
         */
        const getTradingFeeAmount = (
            byTargetAmount: boolean,
            sourceAmount: BigNumberish,
            targetAmount: BigNumberish
        ): BigNumber => {
            if (byTargetAmount) {
                return mulDivC(sourceAmount, PPM_RESOLUTION, PPM_RESOLUTION - DEFAULT_TRADING_FEE_PPM)
                    .sub(sourceAmount)
                    .mul(+1);
            } else {
                return mulDivF(targetAmount, PPM_RESOLUTION - DEFAULT_TRADING_FEE_PPM, PPM_RESOLUTION)
                    .sub(targetAmount)
                    .mul(-1);
            }
        };

        /**
         * returns the expected source and target amounts for a trade including fees
         */
        const expectedSourceTargetAmounts = (
            byTargetAmount: boolean,
            sourceAmount: BigNumberish,
            targetAmount: BigNumberish,
            tradingFeeAmount: BigNumberish
        ) => {
            let expectedSourceAmount;
            let expectedTargetAmount;

            if (byTargetAmount) {
                expectedSourceAmount = BigNumber.from(sourceAmount).add(tradingFeeAmount);
                expectedTargetAmount = targetAmount;
            } else {
                expectedSourceAmount = sourceAmount;
                expectedTargetAmount = BigNumber.from(targetAmount).sub(tradingFeeAmount);
            }

            return { expectedSourceAmount, expectedTargetAmount };
        };

        /**
         * creates strategies based on provided test data.
         * handles approvals and supports the native token
         */
        const createStrategies = async (strategies: TestStrategy[]) => {
            const strategyIds = [];
            for (let i = 0; i < strategies.length; ++i) {
                const strategy = strategies[i];
                // encode orders to values expected by the contract
                const orders = strategy.orders.map((order: any) =>
                    encodeOrder({
                        liquidity: new Decimal(order.liquidity),
                        lowestRate: new Decimal(order.lowestRate),
                        highestRate: new Decimal(order.highestRate),
                        marginalRate: new Decimal(order.marginalRate)
                    })
                );

                let value = BigNumber.from(0);
                for (const i of [0, 1]) {
                    const token = tokens[strategy.orders[i].token];
                    await transfer(deployer, token, marketMaker, orders[i].y);
                    if (token.address !== NATIVE_TOKEN_ADDRESS) {
                        await token.connect(marketMaker).approve(carbonController.address, orders[i].y);
                    } else {
                        value = value.add(orders[i].y);
                    }
                }

                const tx = await carbonController
                    .connect(marketMaker)
                    .createStrategy(
                        tokens[strategy.orders[0].token].address,
                        tokens[strategy.orders[1].token].address,
                        [orders[0], orders[1]],
                        { value }
                    );
                const receipt = await tx.wait();
                const strategyCreatedEvent = receipt.events?.filter((e) => e.event === 'StrategyCreated');
                if (strategyCreatedEvent === undefined) {
                    throw new Error('event retrieval error');
                }
                const id = strategyCreatedEvent[0]?.args?.id;
                strategyIds.push(id);
            }
            return strategyIds;
        };

        /**
         * performs a trade while handling approvals, gas costs, deadline, etc..
         */
        const trade = async (params: TradeParams): Promise<TradeTestReturnValues> => {
            const {
                tradeActions,
                sourceSymbol,
                targetSymbol,
                sourceAmount,
                targetAmount,
                byTargetAmount,
                sendWithExcessNativeTokenValue,
                constraint
            } = params;

            const sourceToken = tokens[sourceSymbol];
            const targetToken = tokens[targetSymbol];

            // add fee to the sourceAmount in case of trading by target amount
            const sourceAmountIncludingTradingFees = byTargetAmount
                ? BigNumber.from(sourceAmount).add(getTradingFeeAmount(true, sourceAmount, 0))
                : BigNumber.from(sourceAmount);

            // keep track of gas usage
            let gasUsed = BigNumber.from(0);

            // approve the trade if necessary
            if (sourceToken.address !== NATIVE_TOKEN_ADDRESS) {
                const tx = await sourceToken
                    .connect(trader)
                    .approve(carbonController.address, sourceAmountIncludingTradingFees);
                const receipt = await tx.wait();
                gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);
            }

            // prepare vars for a trade
            const _constraint = setConstraint(constraint, byTargetAmount, sourceAmountIncludingTradingFees);
            const deadline = (await latest()) + 1000;
            const pc = carbonController.connect(trader);
            let txValue =
                sourceSymbol === TokenSymbol.ETH ? BigNumber.from(sourceAmountIncludingTradingFees) : BigNumber.from(0);

            // optionally - double the sent amount of native token required to complete the trade
            if (sendWithExcessNativeTokenValue) {
                txValue = txValue.mul(2);
            }

            // perform trade
            const tradeFn = byTargetAmount ? pc.tradeByTargetAmount : pc.tradeBySourceAmount;
            const tx = await tradeFn(sourceToken.address, targetToken.address, tradeActions, deadline, _constraint, {
                value: txValue
            });
            const receipt = await tx.wait();
            gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));

            // prepare variables for assertions
            const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);

            return {
                receipt,
                gasUsed,
                tradingFeeAmount,
                value: txValue
            };
        };
    });

    describe('strategies', async () => {
        let deployer: SignerWithAddress;
        let owner: SignerWithAddress;
        let nonAdmin: SignerWithAddress;
        let bntWhale: SignerWithAddress;
        let usdcWhale: SignerWithAddress;
        let daiWhale: SignerWithAddress;
        const tokens: Tokens = {};

        before(async () => {
            const { bnt, usdc, dai } = await getNamedAccounts();
            ({ deployer, bntWhale, usdcWhale, daiWhale } = await getNamedSigners());
            [owner, nonAdmin] = await ethers.getSigners();
            await fundAccount(deployer, toWei(50000));
            await fundAccount(bntWhale);
            await fundAccount(owner);
            await fundAccount(nonAdmin);

            tokens[TokenSymbol.BNT] = await ethers.getContractAt('TestERC20Burnable', bnt);
            tokens[TokenSymbol.DAI] = await ethers.getContractAt('TestERC20Burnable', dai);
            tokens[TokenSymbol.USDC] = await ethers.getContractAt('TestERC20Burnable', usdc);
            tokens[TokenSymbol.ETH] = await createBurnableToken(new TokenData(TokenSymbol.ETH));

            // fund deployer
            await transfer(bntWhale, tokens[TokenSymbol.BNT], deployer.address, toWei(1_000_000));
            await transfer(daiWhale, tokens[TokenSymbol.DAI], deployer.address, toWei(1_000_000));
            await transfer(usdcWhale, tokens[TokenSymbol.USDC], deployer.address, toWei(10_000_000, 6));
        });

        describe('strategy creation', async () => {
            describe('stores the information correctly', async () => {
                const _permutations = [
                    { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.BNT, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.DAI, token1Amount: 100 },

                    { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.BNT, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.DAI, token1Amount: 0 },

                    { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.BNT, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.DAI, token1Amount: 100 },

                    { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.BNT, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.DAI, token1Amount: 0 }
                ];
                for (const { token0, token1, token0Amount, token1Amount } of _permutations) {
                    it(`(${token0}->${token1}) token0Amount: ${token0Amount} | token1Amount: ${token1Amount}`, async () => {
                        // prepare variables
                        const { z, A, B } = generateTestOrder();
                        const _token0 = tokens[token0];
                        const _token1 = tokens[token1];

                        // create strategy
                        const { id } = await createStrategy({
                            token0: _token0,
                            token1: _token1,
                            token0Amount,
                            token1Amount
                        });

                        // fetch the strategy created
                        const strategy = await carbonController.strategy(id);

                        // prepare a result object
                        const result = {
                            id: strategy.id.toString(),
                            owner: strategy.owner,
                            tokens: strategy.tokens,
                            orders: strategy.orders.map((o: any) => ({
                                y: o.y.toString(),
                                z: o.z.toString(),
                                A: o.A.toString(),
                                B: o.B.toString()
                            }))
                        };

                        // prepare the expected result object
                        const amounts = [token0Amount, token1Amount];
                        const _tokens = [tokens[token0], tokens[token1]];

                        const expectedResult: StrategyStruct = {
                            id: id.toString(),
                            owner: owner.address,
                            tokens: [_tokens[0].address, _tokens[1].address],
                            orders: [
                                { y: amounts[0].toString(), z: z.toString(), A: A.toString(), B: B.toString() },
                                { y: amounts[1].toString(), z: z.toString(), A: A.toString(), B: B.toString() }
                            ]
                        };

                        // assert
                        expect(expectedResult).to.deep.equal(result);
                    });
                }
            });

            describe('reverts for non valid addresses', async () => {
                const _permutations = [
                    { token0: TokenSymbol.DAI, token1: ZERO_ADDRESS },
                    { token0: ZERO_ADDRESS, token1: TokenSymbol.BNT },
                    { token0: ZERO_ADDRESS, token1: ZERO_ADDRESS }
                ];

                const order = generateTestOrder();
                for (const { token0, token1 } of _permutations) {
                    it(`(${token0}->${token1})`, async () => {
                        const _token0 = tokens[token0] ? tokens[token0].address : ZERO_ADDRESS;
                        const _token1 = tokens[token1] ? tokens[token1].address : ZERO_ADDRESS;
                        const tx = await carbonController.createStrategy(_token0, _token1, [order, order]);
                        await expect(tx.wait()).to.be.reverted;
                    });
                }
            });

            it('emits the StrategyCreated event', async () => {
                const { y, z, A, B } = generateTestOrder();

                const { tx, id } = await createStrategy();
                await expect(tx)
                    .to.emit(carbonController, 'StrategyCreated')
                    .withArgs(
                        id,
                        owner.address,
                        tokens[TokenSymbol.BNT].address,
                        tokens[TokenSymbol.DAI].address,
                        [BigNumber.from(y), BigNumber.from(z), BigNumber.from(A), BigNumber.from(B)],
                        [BigNumber.from(y), BigNumber.from(z), BigNumber.from(A), BigNumber.from(B)]
                    );
            });

            it('mints a voucher token to the caller', async () => {
                const { id } = await createStrategy();
                const tokenOwner = await voucher.ownerOf(id);
                expect(tokenOwner).to.eq(owner.address);
            });

            it('emits the voucher Transfer event', async () => {
                const { tx, id } = await createStrategy();
                await expect(tx).to.emit(voucher, 'Transfer').withArgs(ZERO_ADDRESS, owner.address, id);
            });

            describe('balances are updated correctly', () => {
                const _permutations = [
                    { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.BNT, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.DAI, token1Amount: 100 },

                    { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.BNT, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 100, token1: TokenSymbol.DAI, token1Amount: 0 },

                    { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.BNT, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 100 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.DAI, token1Amount: 100 },

                    { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.BNT, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 0 },
                    { token0: TokenSymbol.BNT, token0Amount: 0, token1: TokenSymbol.DAI, token1Amount: 0 }
                ];

                for (const { token0, token1, token0Amount, token1Amount } of _permutations) {
                    it(`(${token0}->${token1}) token0Amount: ${token0Amount} | token1Amount: ${token1Amount}`, async () => {
                        // prepare variables
                        const _token0 = tokens[token0];
                        const _token1 = tokens[token1];
                        const amounts = [BigNumber.from(token0Amount), BigNumber.from(token1Amount)];

                        const balanceTypes = [
                            { type: 'ownerToken0', token: _token0, account: owner.address },
                            { type: 'ownerToken1', token: _token1, account: owner.address },
                            { type: 'controllerToken0', token: _token0, account: carbonController.address },
                            { type: 'controllerToken1', token: _token1, account: carbonController.address }
                        ];

                        // fund the owner
                        await transfer(deployer, _token0, owner, amounts[0]);
                        await transfer(deployer, _token1, owner, amounts[1]);

                        // fetch balances before creating
                        const before: any = {};
                        for (const b of balanceTypes) {
                            before[b.type] = await getBalance(b.token, b.account);
                        }

                        // create strategy
                        const { gasUsed } = await createStrategy({
                            token0Amount,
                            token1Amount,
                            token0: _token0,
                            token1: _token1,
                            skipFunding: true
                        });

                        // fetch balances after creating
                        const after: any = {};
                        for (const b of balanceTypes) {
                            after[b.type] = await getBalance(b.token, b.account);
                        }

                        // account for gas costs if the token is the native token;
                        const expectedOwnerAmountToken0 =
                            _token0.address === NATIVE_TOKEN_ADDRESS ? amounts[0].add(gasUsed) : amounts[0];
                        const expectedOwnerAmountToken1 =
                            _token1.address === NATIVE_TOKEN_ADDRESS ? amounts[1].add(gasUsed) : amounts[1];

                        // owner's balance should decrease y amount
                        expect(after.ownerToken0).to.eq(before.ownerToken0.sub(expectedOwnerAmountToken0));
                        expect(after.ownerToken1).to.eq(before.ownerToken1.sub(expectedOwnerAmountToken1));

                        // controller's balance should increase y amount
                        expect(after.controllerToken0).to.eq(before.controllerToken0.add(amounts[0]));
                        expect(after.controllerToken1).to.eq(before.controllerToken1.add(amounts[1]));
                    });
                }
            });

            const SID1 = generateStrategyId(1, 1);

            /**
             * creates a test strategy, handles funding and approvals
             * @returns a createStrategy transaction
             */
            const createStrategy = async (params?: CreateStrategyParams) => {
                // prepare variables
                const _params = { ...params };
                const order = _params.order ? _params.order : generateTestOrder();
                const _owner = _params.owner ? _params.owner : owner;
                const _tokens = [
                    _params.token0 ? _params.token0 : tokens[TokenSymbol.BNT],
                    _params.token1 ? _params.token1 : tokens[TokenSymbol.DAI]
                ];
                const amounts = [order.y, order.y];

                if (_params.token0Amount != null) {
                    amounts[0] = BigNumber.from(_params.token0Amount);
                }

                if (_params.token1Amount != null) {
                    amounts[1] = BigNumber.from(_params.token1Amount);
                }

                // keep track of gas usage
                let gasUsed = BigNumber.from(0);
                let txValue = BigNumber.from(0);

                // fund and approve
                for (let i = 0; i < 2; i++) {
                    const token = _tokens[i];
                    // optionally skip funding
                    if (!_params.skipFunding) {
                        await transfer(deployer, token, owner, amounts[i]);
                    }
                    if (token.address === NATIVE_TOKEN_ADDRESS) {
                        txValue = amounts[i];
                    } else {
                        const tx = await token.connect(_owner).approve(carbonController.address, amounts[i]);
                        const receipt = await tx.wait();
                        gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));
                    }
                }

                if (_params.sendWithExcessNativeTokenValue) {
                    txValue = BigNumber.from(txValue).add(10000);
                }

                // create strategy
                const tx = await carbonController.connect(_owner).createStrategy(
                    _tokens[0].address,
                    _tokens[1].address,
                    [
                        { ...order, y: amounts[0] },
                        { ...order, y: amounts[1] }
                    ],
                    { value: txValue }
                );
                const receipt = await tx.wait();
                gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));
                const strategyCreatedEvent = receipt.events?.filter((e) => e.event === 'StrategyCreated');
                if (strategyCreatedEvent === undefined) {
                    throw new Error('event retrieval error');
                }
                const id = strategyCreatedEvent[0]?.args?.id;

                return { tx, gasUsed, id };
            };

            describe('strategy updating', async () => {
                const _permutations = [
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.DAI,
                        order0Delta: 100,
                        order1Delta: -100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.ETH,
                        order0Delta: 100,
                        order1Delta: -100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.ETH,
                        token1: TokenSymbol.BNT,
                        order0Delta: 100,
                        order1Delta: -100,
                        sendWithExcessNativeTokenValue: false
                    },

                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.DAI,
                        order0Delta: -100,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.ETH,
                        order0Delta: -100,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.ETH,
                        token1: TokenSymbol.BNT,
                        order0Delta: -100,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },

                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.DAI,
                        order0Delta: -100,
                        order1Delta: -100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.ETH,
                        order0Delta: -100,
                        order1Delta: -100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.ETH,
                        token1: TokenSymbol.BNT,
                        order0Delta: -100,
                        order1Delta: -100,
                        sendWithExcessNativeTokenValue: false
                    },

                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.DAI,
                        order0Delta: 100,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.ETH,
                        order0Delta: 100,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.ETH,
                        token1: TokenSymbol.BNT,
                        order0Delta: 100,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },

                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.DAI,
                        order0Delta: 100,
                        order1Delta: 0,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.ETH,
                        order0Delta: 100,
                        order1Delta: 0,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.ETH,
                        token1: TokenSymbol.BNT,
                        order0Delta: 100,
                        order1Delta: 0,
                        sendWithExcessNativeTokenValue: false
                    },

                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.DAI,
                        order0Delta: 0,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.BNT,
                        token1: TokenSymbol.ETH,
                        order0Delta: 0,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    },
                    {
                        token0: TokenSymbol.ETH,
                        token1: TokenSymbol.BNT,
                        order0Delta: 0,
                        order1Delta: 100,
                        sendWithExcessNativeTokenValue: false
                    }
                ];

                describe('orders are stored correctly', async () => {
                    for (const { token0, token1, order0Delta, order1Delta } of _permutations) {
                        it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta}`, async () => {
                            // prepare variables
                            const { y, z, A, B } = generateTestOrder();
                            const _token0 = tokens[token0];
                            const _token1 = tokens[token1];
                            const _tokens = [_token0, _token1];

                            // create strategy
                            const { id } = await createStrategy({ token0: _tokens[0], token1: _tokens[1] });

                            // update strategy
                            await updateStrategy({
                                token0: _tokens[0],
                                token1: _tokens[1],
                                strategyId: id,
                                order0Delta,
                                order1Delta
                            });

                            // fetch the strategy created
                            const strategy = await carbonController.strategy(id);

                            // prepare a result object
                            const result = {
                                id: strategy.id.toString(),
                                owner: strategy.owner,
                                tokens: strategy.tokens,
                                orders: strategy.orders.map((o: any) => ({
                                    y: o.y.toString(),
                                    z: o.z.toString(),
                                    A: o.A.toString(),
                                    B: o.B.toString()
                                }))
                            };

                            // prepare the expected result object
                            const deltas = [order0Delta, order1Delta];
                            const expectedResult: StrategyStruct = {
                                id: id.toString(),
                                owner: owner.address,
                                tokens: [_tokens[0].address, _tokens[1].address],
                                orders: [
                                    {
                                        y: y.add(deltas[0]).toString(),
                                        z: z.add(deltas[0]).toString(),
                                        A: A.add(deltas[0]).toString(),
                                        B: B.add(deltas[0]).toString()
                                    },
                                    {
                                        y: y.add(deltas[1]).toString(),
                                        z: z.add(deltas[1]).toString(),
                                        A: A.add(deltas[1]).toString(),
                                        B: B.add(deltas[1]).toString()
                                    }
                                ]
                            };

                            // assert
                            expect(expectedResult).to.deep.equal(result);
                        });
                    }
                });

                describe('orders are stored correctly without liquidity change', async () => {
                    const _permutations = [
                        { token0: TokenSymbol.BNT, token1: TokenSymbol.DAI, order0Delta: 1, order1Delta: -1 },
                        { token0: TokenSymbol.ETH, token1: TokenSymbol.BNT, order0Delta: 1, order1Delta: -1 },
                        { token0: TokenSymbol.BNT, token1: TokenSymbol.ETH, order0Delta: 1, order1Delta: -1 },

                        { token0: TokenSymbol.BNT, token1: TokenSymbol.DAI, order0Delta: -1, order1Delta: 1 },
                        { token0: TokenSymbol.ETH, token1: TokenSymbol.BNT, order0Delta: -1, order1Delta: 1 },
                        { token0: TokenSymbol.BNT, token1: TokenSymbol.ETH, order0Delta: -1, order1Delta: 1 },

                        { token0: TokenSymbol.BNT, token1: TokenSymbol.DAI, order0Delta: -1, order1Delta: -1 },
                        { token0: TokenSymbol.ETH, token1: TokenSymbol.BNT, order0Delta: -1, order1Delta: -1 },
                        { token0: TokenSymbol.BNT, token1: TokenSymbol.ETH, order0Delta: -1, order1Delta: -1 },

                        { token0: TokenSymbol.BNT, token1: TokenSymbol.DAI, order0Delta: 1, order1Delta: 1 },
                        { token0: TokenSymbol.ETH, token1: TokenSymbol.BNT, order0Delta: 1, order1Delta: 1 },
                        { token0: TokenSymbol.BNT, token1: TokenSymbol.ETH, order0Delta: 1, order1Delta: 1 }
                    ];
                    for (const { token0, token1, order0Delta, order1Delta } of _permutations) {
                        it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta}`, async () => {
                            // prepare variables
                            const order = generateTestOrder();
                            const newOrders: TestOrder[] = [];
                            const _token0 = tokens[token0];
                            const _token1 = tokens[token1];
                            const deltas = [order0Delta, order1Delta];

                            // prepare new orders
                            for (let i = 0; i < 2; i++) {
                                newOrders.push({
                                    y: order.y,
                                    z: order.z.add(deltas[i]),
                                    A: order.A.add(deltas[i]),
                                    B: order.B.add(deltas[i])
                                });
                            }

                            // create strategy
                            const { id } = await createStrategy({ token0: _token0, token1: _token1 });

                            // update strategy
                            await carbonController
                                .connect(owner)
                                .updateStrategy(id, [order, order], [newOrders[0], newOrders[1]]);

                            // fetch the strategy created
                            const strategy = await carbonController.strategy(id);

                            // prepare a result object
                            const result = {
                                id: strategy.id.toString(),
                                owner: strategy.owner,
                                tokens: strategy.tokens,
                                orders: strategy.orders.map((o: any) => ({
                                    y: o.y,
                                    z: o.z,
                                    A: o.A,
                                    B: o.B
                                }))
                            };

                            // prepare the expected result object
                            const expectedResult: StrategyStruct = {
                                id: id.toString(),
                                owner: owner.address,
                                tokens: [_token0.address, _token1.address],
                                orders: [newOrders[0], newOrders[1]]
                            };

                            // assert
                            expect(expectedResult).to.deep.equal(result);
                        });
                    }
                });

                describe('balances are updated correctly', () => {
                    const strategyUpdatingPermutations = [
                        ..._permutations,
                        {
                            token0: TokenSymbol.BNT,
                            token1: TokenSymbol.ETH,
                            order0Delta: 100,
                            order1Delta: 100,
                            sendWithExcessNativeTokenValue: true
                        },
                        {
                            token0: TokenSymbol.ETH,
                            token1: TokenSymbol.BNT,
                            order0Delta: 100,
                            order1Delta: 100,
                            sendWithExcessNativeTokenValue: true
                        }
                    ];
                    for (const {
                        token0,
                        token1,
                        order0Delta,
                        order1Delta,
                        sendWithExcessNativeTokenValue
                    } of strategyUpdatingPermutations) {
                        // eslint-disable-next-line max-len
                        it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta} | excess: ${sendWithExcessNativeTokenValue}`, async () => {
                            // prepare variables
                            const _tokens = [tokens[token0], tokens[token1]];
                            const deltas = [BigNumber.from(order0Delta), BigNumber.from(order1Delta)];

                            const delta0 = deltas[0];
                            const delta1 = deltas[1];
                            const balanceTypes = [
                                { type: 'ownerToken0', token: _tokens[0], account: owner.address },
                                { type: 'ownerToken1', token: _tokens[1], account: owner.address },
                                { type: 'controllerToken0', token: _tokens[0], account: carbonController.address },
                                { type: 'controllerToken1', token: _tokens[1], account: carbonController.address }
                            ];

                            // create strategy
                            const { id } = await createStrategy({ token0: _tokens[0], token1: _tokens[1] });

                            // fund user
                            for (let i = 0; i < 2; i++) {
                                const delta = deltas[i];
                                if (delta.gt(0)) {
                                    await transfer(deployer, _tokens[i], owner, deltas[i]);
                                }
                            }

                            // fetch balances before updating
                            const before: any = {};
                            for (const b of balanceTypes) {
                                before[b.type] = await getBalance(b.token, b.account);
                            }

                            // perform update
                            const { gasUsed } = await updateStrategy({
                                order0Delta,
                                order1Delta,
                                token0: _tokens[0],
                                token1: _tokens[1],
                                strategyId: id,
                                skipFunding: true,
                                sendWithExcessNativeTokenValue
                            });

                            // fetch balances after creating
                            const after: any = {};
                            for (const b of balanceTypes) {
                                after[b.type] = await getBalance(b.token, b.account);
                            }

                            // account for gas costs if the token is the native token;
                            const expectedOwnerDeltaToken0 =
                                _tokens[0].address === NATIVE_TOKEN_ADDRESS ? delta0.add(gasUsed) : delta0;
                            const expectedOwnerDeltaToken1 =
                                _tokens[1].address === NATIVE_TOKEN_ADDRESS ? delta1.add(gasUsed) : delta1;

                            // assert
                            expect(after.ownerToken0).to.eq(before.ownerToken0.sub(expectedOwnerDeltaToken0));
                            expect(after.ownerToken1).to.eq(before.ownerToken1.sub(expectedOwnerDeltaToken1));
                            expect(after.controllerToken0).to.eq(before.controllerToken0.add(delta0));
                            expect(after.controllerToken1).to.eq(before.controllerToken1.add(delta1));
                        });
                    }
                });

                /**
                 * updates a test strategy, handles funding and approvals
                 * @returns an updateStrategy transaction
                 */
                const updateStrategy = async (params?: UpdateStrategyParams) => {
                    const defaults = {
                        owner,
                        token0: tokens[TokenSymbol.BNT],
                        token1: tokens[TokenSymbol.DAI],
                        strategyId: SID1,
                        skipFunding: false,
                        order0Delta: 100,
                        order1Delta: -100
                    };
                    const _params = { ...defaults, ...params };

                    // keep track of gas usage
                    let gasUsed = BigNumber.from(0);

                    const _tokens = [_params.token0, _params.token1];
                    const deltas = [BigNumber.from(_params.order0Delta), BigNumber.from(_params.order1Delta)];

                    let txValue = BigNumber.from(0);
                    for (let i = 0; i < 2; i++) {
                        const token = _tokens[i];
                        const delta = deltas[i];
                        // only positive deltas (deposits) requires funding
                        if (!_params.skipFunding && delta.gt(0)) {
                            await transfer(deployer, token, _params.owner, delta);
                        }

                        if (token.address === NATIVE_TOKEN_ADDRESS) {
                            // only positive deltas (deposits) require funding
                            if (delta.gt(0)) {
                                txValue = txValue.add(delta);
                            }
                        } else {
                            if (delta.gt(0)) {
                                // approve the tx
                                const tx = await token.connect(_params.owner).approve(carbonController.address, delta);

                                // count the gas
                                const receipt = await tx.wait();
                                gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));
                            }
                        }
                    }

                    if (_params.sendWithExcessNativeTokenValue) {
                        txValue = BigNumber.from(txValue).add(10000);
                    }

                    // prepare orders
                    const currentOrder = generateTestOrder();
                    const token0NewOrder = { ...currentOrder };
                    const token1NewOrder = { ...currentOrder };
                    let p: keyof typeof currentOrder;
                    for (p in currentOrder) {
                        token0NewOrder[p] = currentOrder[p].add(deltas[0]);
                        token1NewOrder[p] = currentOrder[p].add(deltas[1]);
                    }

                    // update strategy
                    const tx = await carbonController.connect(owner).updateStrategy(
                        _params.strategyId,

                        [currentOrder, currentOrder],
                        [token0NewOrder, token1NewOrder],
                        {
                            value: txValue
                        }
                    );
                    const receipt = await tx.wait();
                    gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));

                    // return values
                    return { tx, gasUsed };
                };
            });
        });
    });
});
