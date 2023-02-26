import { CarbonController, MasterVault, TestERC20Burnable } from '../../../components/Contracts';
import { TradeActionStruct } from '../../../typechain-types/contracts/carbon/CarbonController';
import { DEFAULT_TRADING_FEE_PPM, MAX_UINT128, PPM_RESOLUTION, ZERO_ADDRESS } from '../../../utils/Constants';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../../utils/TokenData';
import { createBurnableToken, createSystem, Tokens } from '../../helpers/Factory';
import { latest } from '../../helpers/Time';
import { getBalance, transfer } from '../../helpers/Utils';
import { decodeOrder, encodeOrder } from '../../utility/carbon-sdk';
import { FactoryOptions, testCaseFactory, TestStrategy, TestTradeActions } from './testDataFactory';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumber, BigNumberish, ContractReceipt } from 'ethers';
import { ethers } from 'hardhat';

type TradeTestReturnValues = {
    tradingFeeAmount: BigNumber;
    gasUsed: BigNumber;
    receipt: ContractReceipt;
    value: BigNumber;
};

type TradeParams = {
    tradeActions: TestTradeActions[];
    sourceSymbol: string;
    targetSymbol: string;
    sourceAmount: BigNumberish;
    targetAmount: BigNumberish;
    byTargetAmount: boolean;
    sendWithExcessNativeTokenValue?: boolean;
    constraint?: BigNumberish;
};

type SimpleTradeParams = {
    sourceToken: string;
    targetToken: string;
    byTargetAmount: boolean;
    sourceAmount: BigNumberish;
    tradeActions?: TradeActionStruct[];
    deadlineDelta?: number;
    txValue?: BigNumberish;
    constraint?: BigNumberish;
};

const mulDivF = (x: BigNumberish, y: BigNumberish, z: BigNumberish) => BigNumber.from(x).mul(y).div(z);
const mulDivC = (x: BigNumberish, y: BigNumberish, z: BigNumberish) => BigNumber.from(x).mul(y).add(z).sub(1).div(z);
const toFixed = (x: Decimal) => new Decimal(x.toFixed(12)).toFixed();

const setConstraint = (
    constraint: BigNumberish | undefined,
    byTargetAmount: boolean,
    expectedResultAmount: BigNumberish
): BigNumberish => {
    if (!constraint && constraint !== 0) {
        return byTargetAmount ? expectedResultAmount : 1;
    }
    return constraint;
};

const permutations: FactoryOptions[] = [
    { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: true, inverseOrders: true },
    { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: true, inverseOrders: false },
    { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: false, inverseOrders: true },
    { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: false, inverseOrders: false },

    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: true, inverseOrders: true },
    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: true, inverseOrders: false },
    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: false, inverseOrders: true },
    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: false, inverseOrders: false },

    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true, inverseOrders: true },
    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true, inverseOrders: false },
    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: false, inverseOrders: true },
    { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: false, inverseOrders: false }
];

describe('Trading', () => {
    let deployer: SignerWithAddress;
    let marketMaker: SignerWithAddress;
    let trader: SignerWithAddress;
    let carbonController: CarbonController;
    let token0: TestERC20Burnable;
    let token1: TestERC20Burnable;
    let masterVault: MasterVault;
    let tokens: Tokens = {};

    before(async () => {
        [deployer, marketMaker, trader] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ carbonController, masterVault } = await createSystem());

        tokens = {};
        for (const symbol of [
            TokenSymbol.ETH,
            TokenSymbol.USDC,
            TokenSymbol.TKN0,
            TokenSymbol.TKN1,
            TokenSymbol.TKN2
        ]) {
            tokens[symbol] = await createBurnableToken(new TokenData(symbol));
        }
        token0 = tokens[TokenSymbol.TKN0];
        token1 = tokens[TokenSymbol.TKN1];
    });

    /**
     * creates strategies based on provided test data.
     * handles approvals and supports the native token
     */
    const createStrategies = async (strategies: TestStrategy[]) => {
        for (let i = 0; i < strategies.length; i++) {
            const strategy = strategies[i];
            // encode orders to values expected by the contract
            const orders = strategy.orders.map((order) =>
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

            await carbonController
                .connect(marketMaker)
                .createStrategy(
                    tokens[strategy.orders[0].token].address,
                    tokens[strategy.orders[1].token].address,
                    [orders[0], orders[1]],
                    { value }
                );
        }
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

    /**
     * performs a static call to the trade function, returning the value returned by the contract
     */
    const tradeStatic = async (params: TradeParams): Promise<BigNumber> => {
        const {
            tradeActions,
            sourceSymbol,
            targetSymbol,
            sourceAmount,
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

        // approve the trade if necessary
        if (sourceToken.address !== NATIVE_TOKEN_ADDRESS) {
            await sourceToken.connect(trader).approve(carbonController.address, sourceAmountIncludingTradingFees);
        }

        // double the sent amount of native token required to complete the trade
        let txValue =
            sourceSymbol === TokenSymbol.ETH ? BigNumber.from(sourceAmountIncludingTradingFees) : BigNumber.from(0);
        if (sendWithExcessNativeTokenValue) {
            txValue = txValue.mul(2);
        }

        // prepare vars for a trade
        const _constraint = setConstraint(constraint, byTargetAmount, sourceAmountIncludingTradingFees);
        const deadline = (await latest()) + 1000;
        const pc = carbonController.connect(trader);

        // perform static trade
        const tradeFn = byTargetAmount ? pc.callStatic.tradeByTargetAmount : pc.callStatic.tradeBySourceAmount;
        return tradeFn(sourceToken.address, targetToken.address, tradeActions, deadline, _constraint, {
            value: txValue
        });
    };

    /**
     * simple wrapper that helps choose target/source function and fills the trade function arguments
     */
    const simpleTrade = async (params: SimpleTradeParams) => {
        const {
            sourceToken,
            targetToken,
            byTargetAmount,
            constraint,
            sourceAmount,
            deadlineDelta = 1000,
            tradeActions = [],
            txValue = 0
        } = params;
        const pc = carbonController.connect(trader);

        const _constraint = setConstraint(constraint, byTargetAmount, sourceAmount);

        const tradeFn = byTargetAmount ? pc.tradeByTargetAmount : pc.tradeBySourceAmount;
        const deadline = (await latest()) + deadlineDelta;

        return tradeFn(sourceToken, targetToken, tradeActions, deadline, _constraint, { value: txValue });
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

    describe('validations', () => {
        describe('reverts when identical tokens are provided', async () => {
            const permutations = [{ byTargetAmount: false }, { byTargetAmount: true }];
            for (const { byTargetAmount } of permutations) {
                it(`byTargetAmount: ${byTargetAmount}`, async () => {
                    await expect(
                        simpleTrade({
                            sourceToken: token0.address,
                            targetToken: token0.address,
                            byTargetAmount,
                            sourceAmount: 1
                        })
                    ).to.be.revertedWithError('IdenticalAddresses');
                });
            }
        });

        describe('reverts when the constraint is not valid', async () => {
            const permutations = [{ byTargetAmount: false }, { byTargetAmount: true }];
            for (const { byTargetAmount } of permutations) {
                it(`byTargetAmount: ${byTargetAmount}`, async () => {
                    await expect(
                        simpleTrade({
                            byTargetAmount,
                            constraint: 0,
                            sourceToken: token0.address,
                            targetToken: token1.address,
                            sourceAmount: 1
                        })
                    ).to.be.revertedWithError('ZeroValue');
                });
            }
        });

        describe('reverts if insufficient native token was sent', () => {
            const permutations = [
                {
                    sourceSymbol: TokenSymbol.ETH,
                    targetSymbol: TokenSymbol.TKN0,
                    byTargetAmount: false,
                    revertError: 'NativeAmountMismatch'
                },
                {
                    sourceSymbol: TokenSymbol.ETH,
                    targetSymbol: TokenSymbol.TKN0,
                    byTargetAmount: true,
                    revertError: 'InsufficientNativeTokenReceived'
                }
            ];

            for (const { sourceSymbol, targetSymbol, byTargetAmount, revertError } of permutations) {
                it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                    // create test case
                    const testCase = testCaseFactory({
                        sourceSymbol,
                        targetSymbol,
                        byTargetAmount
                    });

                    // create strategies
                    await createStrategies(testCase.strategies);

                    // fund user for a trade
                    const { sourceAmount } = testCase;
                    await transfer(deployer, tokens[sourceSymbol], trader, sourceAmount);

                    // assert
                    await expect(
                        simpleTrade({
                            byTargetAmount,
                            sourceAmount,
                            sourceToken: tokens[sourceSymbol].address,
                            targetToken: tokens[targetSymbol].address,
                            tradeActions: testCase.tradeActions,
                            txValue: BigNumber.from(sourceAmount).div(2)
                        })
                    ).to.be.revertedWithError(revertError);
                });
            }
        });

        describe('reverts if unnecessary native token was sent', () => {
            const permutations: FactoryOptions[] = [
                {
                    sourceSymbol: TokenSymbol.TKN0,
                    targetSymbol: TokenSymbol.TKN1,
                    byTargetAmount: false
                },
                {
                    sourceSymbol: TokenSymbol.TKN0,
                    targetSymbol: TokenSymbol.TKN1,
                    byTargetAmount: true
                }
            ];

            for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
                it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                    // create test case
                    const testCase = testCaseFactory({
                        sourceSymbol,
                        targetSymbol,
                        byTargetAmount
                    });

                    // create strategies
                    await createStrategies(testCase.strategies);

                    // fund user for a trade
                    const { sourceAmount } = testCase;
                    await transfer(deployer, tokens[sourceSymbol], trader, sourceAmount);

                    // assert trade between 2 tokens, but send some native token anyway
                    await expect(
                        simpleTrade({
                            sourceAmount,
                            sourceToken: tokens[sourceSymbol].address,
                            targetToken: tokens[targetSymbol].address,
                            tradeActions: testCase.tradeActions,
                            txValue: sourceAmount,
                            byTargetAmount
                        })
                    ).to.be.revertedWithError('UnnecessaryNativeTokenReceived');
                });
            }
        });

        describe('reverts if deadline has expired', () => {
            const permutations = [{ byTargetAmount: false }, { byTargetAmount: true }];
            for (const { byTargetAmount } of permutations) {
                it(`byTargetAmount: ${byTargetAmount}`, async () => {
                    await expect(
                        simpleTrade({
                            sourceToken: token0.address,
                            targetToken: token1.address,
                            deadlineDelta: -1000,
                            sourceAmount: 1,
                            byTargetAmount
                        })
                    ).to.be.revertedWithError('DeadlineExpired');
                });
            }
        });

        describe('reverts if tradeActions are provided with 0 amount', () => {
            const permutations = [{ byTargetAmount: false }, { byTargetAmount: true }];
            for (const { byTargetAmount } of permutations) {
                it(`byTargetAmount: ${byTargetAmount}`, async () => {
                    const testCase = testCaseFactory({
                        byTargetAmount,
                        sourceSymbol: TokenSymbol.TKN0,
                        targetSymbol: TokenSymbol.TKN1
                    });
                    // create exactly 2 strategies
                    await createStrategies(testCase.strategies.slice(0, 3));

                    // assert
                    await expect(
                        simpleTrade({
                            sourceToken: token0.address,
                            targetToken: token1.address,
                            sourceAmount: 1,
                            byTargetAmount,
                            tradeActions: [
                                { strategyId: 1, amount: 1 },
                                { strategyId: 2, amount: 0 }
                            ]
                        })
                    ).to.be.revertedWithError('InvalidTradeActionAmount');
                });
            }
        });

        describe('reverts if tradeActions provided with strategyIds not matching the source/target tokens', () => {
            const permutations = [{ byTargetAmount: false }, { byTargetAmount: true }];
            for (const { byTargetAmount } of permutations) {
                it(`byTargetAmount: ${byTargetAmount}`, async () => {
                    // create testCase and strategies to use for assertions
                    const testCase = testCaseFactory({
                        byTargetAmount,
                        sourceSymbol: TokenSymbol.ETH,
                        targetSymbol: TokenSymbol.TKN0
                    });
                    const { strategies, sourceAmount, tradeActions } = testCase;
                    await createStrategies(strategies);

                    // edit one of the actions to use the extra strategy created
                    tradeActions[2].strategyId = strategies.length.toString();

                    // create additional strategies using different tokens
                    const testCase2 = testCaseFactory({
                        byTargetAmount,
                        sourceSymbol: TokenSymbol.TKN1,
                        targetSymbol: TokenSymbol.TKN2
                    });
                    await createStrategies(testCase2.strategies);

                    // assert
                    await expect(
                        simpleTrade({
                            sourceAmount,
                            tradeActions,
                            byTargetAmount,
                            sourceToken: tokens[TokenSymbol.ETH].address,
                            targetToken: tokens[TokenSymbol.TKN1].address
                        })
                    ).to.be.revertedWithError('TokensMismatch');
                });
            }
        });

        describe('reverts if tradeActions provided with strategyIds that do not exist', () => {
            const permutations = [{ byTargetAmount: false }, { byTargetAmount: true }];
            for (const { byTargetAmount } of permutations) {
                it(`byTargetAmount: ${byTargetAmount}`, async () => {
                    // create testCase and strategies to use for assertions
                    const testCase = testCaseFactory({
                        byTargetAmount,
                        sourceSymbol: TokenSymbol.ETH,
                        targetSymbol: TokenSymbol.TKN0
                    });
                    const { strategies, sourceAmount, tradeActions } = testCase;
                    await createStrategies(strategies);

                    // edit one of the actions to use a strategy that does not exist
                    tradeActions[2].strategyId = (strategies.length + 1).toString();

                    // assert
                    await expect(
                        simpleTrade({
                            sourceAmount,
                            tradeActions,
                            byTargetAmount,
                            sourceToken: tokens[TokenSymbol.ETH].address,
                            targetToken: tokens[TokenSymbol.TKN0].address
                        })
                    ).to.be.revertedWithError('StrategyDoesNotExist');
                });
            }
        });

        describe('reverts when one of or both addresses are zero address', async () => {
            const permutations: FactoryOptions[] = [
                { sourceSymbol: TokenSymbol.TKN0, targetSymbol: 'ZERO_ADDRESS', byTargetAmount: true },
                { sourceSymbol: 'ZERO_ADDRESS', targetSymbol: TokenSymbol.TKN0, byTargetAmount: true },
                { sourceSymbol: 'ZERO_ADDRESS', targetSymbol: 'ZERO_ADDRESS', byTargetAmount: true },
                { sourceSymbol: TokenSymbol.TKN0, targetSymbol: 'ZERO_ADDRESS', byTargetAmount: false },
                { sourceSymbol: 'ZERO_ADDRESS', targetSymbol: TokenSymbol.TKN0, byTargetAmount: false },
                { sourceSymbol: 'ZERO_ADDRESS', targetSymbol: 'ZERO_ADDRESS', byTargetAmount: false }
            ];
            for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
                it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                    const sourceToken = sourceSymbol === 'ZERO_ADDRESS' ? ZERO_ADDRESS : tokens[sourceSymbol].address;
                    const targetToken = targetSymbol === 'ZERO_ADDRESS' ? ZERO_ADDRESS : tokens[targetSymbol].address;

                    await expect(
                        simpleTrade({ sourceToken, targetToken, byTargetAmount, sourceAmount: 1 })
                    ).to.be.revertedWithError('InvalidAddress');
                });
            }
        });

        describe('reverts when minReturn or maxInput constraints are unmet', () => {
            const permutations = [
                {
                    sourceSymbol: TokenSymbol.TKN0,
                    targetSymbol: TokenSymbol.TKN1,
                    byTargetAmount: false,
                    constraint: MAX_UINT128,
                    name: 'minReturn',
                    revertError: 'LowerThanMinReturn'
                },
                {
                    sourceSymbol: TokenSymbol.TKN0,
                    targetSymbol: TokenSymbol.TKN1,
                    byTargetAmount: true,
                    constraint: 1,
                    name: 'maxInput',
                    revertError: 'GreaterThanMaxInput'
                }
            ];
            for (const { sourceSymbol, targetSymbol, byTargetAmount, constraint, name, revertError } of permutations) {
                it(`${name}`, async () => {
                    const testCase = testCaseFactory({
                        byTargetAmount,
                        sourceSymbol,
                        targetSymbol
                    });

                    await createStrategies(testCase.strategies);
                    const { sourceAmount } = testCase;

                    await expect(
                        simpleTrade({
                            constraint,
                            byTargetAmount,
                            sourceAmount,
                            sourceToken: tokens[sourceSymbol].address,
                            targetToken: tokens[targetSymbol].address,
                            tradeActions: testCase.tradeActions
                        })
                    ).to.be.revertedWithError(revertError);
                });
            }
        });

        it("reverts if the tx's value is lower than the maxInput constraint", async () => {
            await expect(
                simpleTrade({
                    sourceToken: tokens[TokenSymbol.ETH].address,
                    targetToken: token0.address,
                    byTargetAmount: true,
                    constraint: 1000,
                    txValue: 500,
                    sourceAmount: 1
                })
            ).to.be.revertedWithError('InsufficientNativeTokenReceived');
        });
    });

    describe('trading fees collected are stored AND returned correctly', async () => {
        const permutations: FactoryOptions[] = [
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: true }
        ];

        for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                // create a test case
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount
                });

                // create strategies
                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // perform trade
                await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });

                // prepare data for assertions
                const sourceTokenFees = await carbonController.accumulatedFees(tokens[testCase.sourceSymbol].address);
                const targetTokenFees = await carbonController.accumulatedFees(tokens[testCase.targetSymbol].address);
                const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);

                // assert
                if (byTargetAmount) {
                    expect(sourceTokenFees).to.eq(tradingFeeAmount);
                    expect(targetTokenFees).to.eq(0);
                } else {
                    expect(sourceTokenFees).to.eq(0);
                    expect(targetTokenFees).to.eq(tradingFeeAmount);
                }
            });
        }
    });

    describe('allows trading with tradingFree set to 0', async () => {
        const permutations: FactoryOptions[] = [
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true }
        ];

        for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                // create a test case
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount
                });

                // create strategies
                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // set trading fee to 0
                await carbonController.setTradingFeePPM(0);

                // perform trade
                const { receipt } = await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });

                // assert
                if (!receipt || !receipt.events) {
                    expect.fail('no events emitted');
                }

                const event = receipt.events[receipt.events.length - 1];
                if (!event.args) {
                    expect.fail('event emitted without args');
                }

                // prepare data for assertions
                const sourceTokenFees = await carbonController.accumulatedFees(tokens[testCase.sourceSymbol].address);
                const targetTokenFees = await carbonController.accumulatedFees(tokens[testCase.targetSymbol].address);
                const eventArgs = event.args;

                // assert
                expect(sourceTokenFees).to.eq(0);
                expect(targetTokenFees).to.eq(0);
                expect(eventArgs.sourceAmount).to.eq(sourceAmount);
                expect(eventArgs.targetAmount).to.eq(targetAmount);
                expect(eventArgs.tradingFeeAmount).to.eq(0);
                expect(event.event).to.eq('TokensTraded');
            });
        }
    });

    describe('emits StrategyUpdated event for every trade action', () => {
        for (const { sourceSymbol, targetSymbol, byTargetAmount, inverseOrders } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount} | inverseOrders: ${inverseOrders}`, async () => {
                const testCase = testCaseFactory({ sourceSymbol, targetSymbol, byTargetAmount, inverseOrders });

                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // perform trade
                const { receipt } = await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });

                // assert
                if (!receipt || !receipt.events) {
                    expect.fail('No events emitted');
                }
                const tradeActionsAmount = testCase.tradeActions.length;
                for (let i = 0; i < tradeActionsAmount; i++) {
                    const strategy = testCase.strategies[i];
                    const event = receipt.events[i];
                    if (!event.args) {
                        expect.fail('Event contains no args');
                    }
                    for (let x = 0; x < 2; x++) {
                        const expectedOrder = strategy.orders[x].expected;
                        const emittedOrder = decodeOrder(event.args[`order${x}`]);
                        expect(emittedOrder.liquidity.toFixed()).to.eq(expectedOrder.liquidity);
                        expect(toFixed(emittedOrder.lowestRate)).to.eq(expectedOrder.lowestRate);
                        expect(toFixed(emittedOrder.highestRate)).to.eq(expectedOrder.highestRate);
                        expect(toFixed(emittedOrder.marginalRate)).to.eq(expectedOrder.marginalRate);
                        expect(event.args.owner).to.eq(marketMaker.address);
                        expect(event.event).to.eq('StrategyUpdated');
                    }
                }
            });
        }
    });

    describe('emits TokensTraded event following a trade', () => {
        for (const { sourceSymbol, targetSymbol, byTargetAmount, inverseOrders } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount} | inverseOrders: ${inverseOrders}`, async () => {
                const testCase = testCaseFactory({ sourceSymbol, targetSymbol, byTargetAmount, inverseOrders });
                const sourceToken = tokens[sourceSymbol];
                const targetToken = tokens[targetSymbol];
                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // perform trade
                const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);
                const { receipt } = await trade({
                    sourceAmount,
                    targetAmount,
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount,
                    tradeActions: testCase.tradeActions
                });

                // assert
                if (!receipt || !receipt.events) {
                    expect.fail('no events emitted');
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

                const eventArgs = event.args;
                expect(eventArgs.sourceToken).to.eq(sourceToken.address);
                expect(eventArgs.targetToken).to.eq(targetToken.address);
                expect(eventArgs.sourceAmount).to.eq(expectedSourceAmount);
                expect(eventArgs.targetAmount).to.eq(expectedTargetAmount);
                expect(eventArgs.tradingFeeAmount).to.eq(tradingFeeAmount);
                expect(eventArgs.byTargetAmount).to.eq(byTargetAmount);
                expect(event.event).to.eq('TokensTraded');
            });
        }
    });

    describe('orders are stored correctly', () => {
        // add cases where the marginal and high rates are equal
        const _permutations = [
            ...permutations,
            {
                sourceSymbol: TokenSymbol.TKN0,
                targetSymbol: TokenSymbol.TKN1,
                byTargetAmount: false,
                inverseOrders: false,
                equalHighestAndMarginalRate: true
            },
            {
                sourceSymbol: TokenSymbol.TKN0,
                targetSymbol: TokenSymbol.TKN1,
                byTargetAmount: true,
                inverseOrders: false,
                equalHighestAndMarginalRate: true
            }
        ];
        for (const {
            sourceSymbol,
            targetSymbol,
            byTargetAmount,
            inverseOrders,
            equalHighestAndMarginalRate
        } of _permutations) {
            // eslint-disable-next-line max-len
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount} | inverseOrders: ${inverseOrders} | equalHighestAndMarginalRate: ${
                equalHighestAndMarginalRate === true
            }`, async () => {
                // create a test case
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount,
                    inverseOrders,
                    equalHighestAndMarginalRate
                });

                // create strategies
                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // perform trade
                await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });

                // fetch updated data from the chain
                const token0 = tokens[testCase.sourceSymbol];
                const token1 = tokens[testCase.targetSymbol];
                const strategies = await carbonController.strategiesByPool(token0.address, token1.address, 0, 0);

                // assertions
                strategies.forEach((strategy, i) => {
                    strategy.orders.forEach((order, x) => {
                        const { y, z, A, B } = order;
                        const encodedOrder = decodeOrder({ y, z, A, B });
                        const expectedOrder = testCase.strategies[i].orders[x].expected;

                        expect(encodedOrder.liquidity.toFixed()).to.eq(expectedOrder.liquidity);
                        expect(toFixed(encodedOrder.lowestRate)).to.eq(expectedOrder.lowestRate);
                        expect(toFixed(encodedOrder.highestRate)).to.eq(expectedOrder.highestRate);
                        expect(toFixed(encodedOrder.marginalRate)).to.eq(expectedOrder.marginalRate);
                    });
                });
            });
        }
    });

    describe('irrelevant strategies remains unchanged following a trade', () => {
        for (const { sourceSymbol, targetSymbol, byTargetAmount, inverseOrders } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount} | inverseOrders: ${inverseOrders}`, async () => {
                // create a testCase
                let testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount,
                    inverseOrders
                });
                if (testCase.strategies.length < 2) {
                    expect.fail('This test requires a testCase with multiple strategies');
                }

                // discard all but 1 tradeAction
                testCase = { ...testCase, tradeActions: [testCase.tradeActions[0]] };

                // create strategies
                await createStrategies(testCase.strategies);

                // save current state for later assertions
                const token0 = tokens[testCase.sourceSymbol];
                const token1 = tokens[testCase.targetSymbol];
                const currentStrategies = await carbonController.strategiesByPool(token0.address, token1.address, 0, 0);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // perform trade
                await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });

                // fetch updated data from the chain
                const newStrategies = await carbonController.strategiesByPool(token0.address, token1.address, 0, 0);

                // assertions
                newStrategies.forEach((newStrategy, i) => {
                    newStrategy.orders.forEach((newOrder, x) => {
                        if (i === 0) {
                            // first order should have been updated with new values
                            const { y, z, A, B } = newOrder;
                            const encodedOrder = decodeOrder({ y, z, A, B });
                            const expectedOrder = testCase.strategies[i].orders[x].expected;
                            expect(encodedOrder.liquidity.toFixed()).to.eq(expectedOrder.liquidity);
                            expect(toFixed(encodedOrder.lowestRate)).to.eq(expectedOrder.lowestRate);
                            expect(toFixed(encodedOrder.highestRate)).to.eq(expectedOrder.highestRate);
                            expect(toFixed(encodedOrder.marginalRate)).to.eq(expectedOrder.marginalRate);
                        } else {
                            // the rest should remain unchanged
                            const currentOrder = currentStrategies[i].orders[x];
                            expect(currentOrder.y).to.eq(newOrder.y);
                            expect(currentOrder.z).to.eq(newOrder.z);
                            expect(currentOrder.A).to.eq(newOrder.A);
                            expect(currentOrder.B).to.eq(newOrder.B);
                        }
                    });
                });
            });
        }
    });

    describe('balances are updated correctly', () => {
        for (const { sourceSymbol, targetSymbol, byTargetAmount, inverseOrders } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount} | inverseOrders: ${inverseOrders}`, async () => {
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount,
                    inverseOrders
                });
                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // organize relevant balances for assertions
                const balanceTypes = [
                    { type: 'traderSource', symbol: sourceSymbol, account: trader.address },
                    { type: 'traderTarget', symbol: targetSymbol, account: trader.address },
                    { type: 'vaultSource', symbol: sourceSymbol, account: masterVault.address },
                    { type: 'vaultTarget', symbol: targetSymbol, account: masterVault.address }
                ];

                // fetch balances prior to trading
                const previousBalances: any = {};
                for (const b of balanceTypes) {
                    previousBalances[b.type] = await getBalance(tokens[b.symbol], b.account);
                }

                // trade
                const { gasUsed, tradingFeeAmount } = await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });

                // fetch balances post trading
                const newBalances: any = {};
                for (const b of balanceTypes) {
                    newBalances[b.type] = await getBalance(tokens[b.symbol], b.account);
                    if (b.symbol === TokenSymbol.ETH) {
                        if (['traderSource', 'traderTarget'].includes(b.type)) {
                            newBalances[b.type] = newBalances[b.type].add(gasUsed);
                        }
                    }
                }

                // prepare variables for assertions
                const { expectedSourceAmount, expectedTargetAmount } = expectedSourceTargetAmounts(
                    byTargetAmount,
                    sourceAmount,
                    targetAmount,
                    tradingFeeAmount
                );

                // assert
                expect(newBalances.traderTarget.sub(previousBalances.traderTarget)).to.eq(expectedTargetAmount);
                expect(previousBalances.traderSource.sub(newBalances.traderSource)).to.eq(expectedSourceAmount);
                expect(newBalances.vaultSource.sub(previousBalances.vaultSource)).to.eq(expectedSourceAmount);
                expect(previousBalances.vaultTarget.sub(newBalances.vaultTarget)).to.eq(expectedTargetAmount);
            });
        }
    });

    describe('excess native token is refunded', () => {
        const permutations: FactoryOptions[] = [
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: true }
        ];

        for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                // create test case
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount
                });

                // create strategies
                await createStrategies(testCase.strategies);

                // (over)fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                const overFundedAmount = BigNumber.from(sourceAmount).mul(2);
                await transfer(deployer, tokens[sourceSymbol], trader, overFundedAmount);

                // organize relevant balances for assertions
                const balanceTypes = [
                    { type: 'traderSource', symbol: sourceSymbol, account: trader.address },
                    { type: 'traderTarget', symbol: targetSymbol, account: trader.address },
                    { type: 'vaultSource', symbol: sourceSymbol, account: masterVault.address },
                    { type: 'vaultTarget', symbol: targetSymbol, account: masterVault.address }
                ];

                // fetch balances prior to trading
                const previousBalances: any = {};
                for (const b of balanceTypes) {
                    previousBalances[b.type] = await getBalance(tokens[b.symbol], b.account);
                }

                // trade
                const { gasUsed, tradingFeeAmount } = await trade({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount,
                    sendWithExcessNativeTokenValue: true
                });

                // fetch balances post trading
                const newBalances: any = {};
                for (const b of balanceTypes) {
                    newBalances[b.type] = await getBalance(tokens[b.symbol], b.account);
                    if (b.symbol === TokenSymbol.ETH) {
                        if (['traderSource', 'traderTarget'].includes(b.type)) {
                            newBalances[b.type] = newBalances[b.type].add(gasUsed);
                        }
                    }
                }

                // prepare variables for assertions
                const { expectedSourceAmount, expectedTargetAmount } = expectedSourceTargetAmounts(
                    byTargetAmount,
                    sourceAmount,
                    targetAmount,
                    tradingFeeAmount
                );

                // assert
                expect(newBalances.traderTarget.sub(previousBalances.traderTarget)).to.eq(expectedTargetAmount);
                expect(previousBalances.traderSource.sub(newBalances.traderSource)).to.eq(expectedSourceAmount);
                expect(newBalances.vaultSource.sub(previousBalances.vaultSource)).to.eq(expectedSourceAmount);
                expect(previousBalances.vaultTarget.sub(newBalances.vaultTarget)).to.eq(expectedTargetAmount);
            });
        }
    });

    describe('trading functions return amounts', () => {
        const permutations = [
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true }
        ];

        for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                // create test case
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount
                });

                // create strategies
                await createStrategies(testCase.strategies);

                // fund user for a trade
                const { sourceAmount, targetAmount } = testCase;
                await fundTrader(sourceAmount, targetAmount, byTargetAmount, sourceSymbol);

                // prepare variables for assertions
                const staticReturnValue = await tradeStatic({
                    sourceAmount,
                    targetAmount,
                    tradeActions: testCase.tradeActions,
                    sourceSymbol: testCase.sourceSymbol,
                    targetSymbol: testCase.targetSymbol,
                    byTargetAmount: testCase.byTargetAmount
                });
                const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);
                const { expectedSourceAmount, expectedTargetAmount } = expectedSourceTargetAmounts(
                    byTargetAmount,
                    sourceAmount,
                    targetAmount,
                    tradingFeeAmount
                );
                const expected = byTargetAmount ? expectedSourceAmount : expectedTargetAmount;

                // assert
                expect(staticReturnValue).to.eq(expected);
            });
        }
    });

    describe('trading amount functions return values', () => {
        const permutations = [
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: false },
            { sourceSymbol: TokenSymbol.ETH, targetSymbol: TokenSymbol.TKN0, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.ETH, byTargetAmount: true },
            { sourceSymbol: TokenSymbol.TKN0, targetSymbol: TokenSymbol.TKN1, byTargetAmount: true }
        ];

        for (const { sourceSymbol, targetSymbol, byTargetAmount } of permutations) {
            it(`(${sourceSymbol}->${targetSymbol}) | byTargetAmount: ${byTargetAmount}`, async () => {
                // create test case
                const testCase = testCaseFactory({
                    sourceSymbol,
                    targetSymbol,
                    byTargetAmount
                });

                // create strategies
                await createStrategies(testCase.strategies);

                const { sourceAmount, targetAmount } = testCase;
                const amountFn = byTargetAmount
                    ? carbonController.tradeSourceAmount
                    : carbonController.tradeTargetAmount;
                const result = await amountFn(
                    tokens[sourceSymbol].address,
                    tokens[targetSymbol].address,
                    testCase.tradeActions
                );

                // prepare variables for assertions
                const tradingFeeAmount = getTradingFeeAmount(byTargetAmount, sourceAmount, targetAmount);
                const { expectedSourceAmount, expectedTargetAmount } = expectedSourceTargetAmounts(
                    byTargetAmount,
                    sourceAmount,
                    targetAmount,
                    tradingFeeAmount
                );
                const expected = byTargetAmount ? expectedSourceAmount : expectedTargetAmount;

                // assert
                expect(result).to.eq(expected);
            });
        }
    });
});
