import {
    testCaseTemplateBySourceAmount,
    testCaseTemplateBySourceAmountEqualHighestAndMarginalRate,
    testCaseTemplateByTargetAmount,
    testCaseTemplateByTargetAmountEqualHighestAndMarginalRate
} from '../helpers/data/tradeTestDataHardhat.json';

export interface ExpectedOrder {
    liquidity: string;
    lowestRate: string;
    highestRate: string;
    marginalRate: string;
}

export interface TestOrder {
    token: string;
    liquidity: string;
    lowestRate: string;
    highestRate: string;
    marginalRate: string;
    expected: ExpectedOrder;
}

export interface TestStrategy {
    orders: TestOrder[];
}

export interface TestTradeActions {
    strategyId: string;
    amount: string;
}

export interface FactoryOptions {
    sourceSymbol: string;
    targetSymbol: string;
    byTargetAmount: boolean;
    inverseOrders?: boolean;
    equalHighestAndMarginalRate?: boolean;
}

export interface TestData {
    sourceSymbol: string;
    targetSymbol: string;
    strategies: TestStrategy[];
    tradeActions: TestTradeActions[];
    byTargetAmount: boolean;
    sourceAmount: string;
    targetAmount: string;
}

export const testCaseFactory = (options: FactoryOptions): TestData => {
    const { sourceSymbol, targetSymbol, byTargetAmount, inverseOrders, equalHighestAndMarginalRate } = options;
    let testCase: TestData;

    if (equalHighestAndMarginalRate) {
        testCase = byTargetAmount
            ? JSON.parse(JSON.stringify(testCaseTemplateByTargetAmountEqualHighestAndMarginalRate))
            : JSON.parse(JSON.stringify(testCaseTemplateBySourceAmountEqualHighestAndMarginalRate));
    } else {
        testCase = byTargetAmount
            ? JSON.parse(JSON.stringify(testCaseTemplateByTargetAmount))
            : JSON.parse(JSON.stringify(testCaseTemplateBySourceAmount));
    }

    testCase.sourceSymbol = sourceSymbol;
    testCase.targetSymbol = targetSymbol;

    testCase.strategies.forEach((s, i) => {
        s.orders[0].token = sourceSymbol;
        s.orders[1].token = targetSymbol;

        if (inverseOrders) {
            if (i % 2 === 0) {
                const temp = s.orders[0];
                s.orders[0] = s.orders[1];
                s.orders[1] = temp;
            }
        }
    });

    return testCase;
};
