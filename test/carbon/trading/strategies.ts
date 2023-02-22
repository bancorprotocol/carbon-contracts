import Contracts, { TestStrategies } from '../../../components/Contracts';
import { encodeOrder } from '../../utility/carbon-sdk';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import Decimal from 'decimal.js';

import ArbitraryTrade from './data/ArbitraryTrade.json';
import EthUsdcTrade from './data/EthUsdcTrade.json';
import ExtremeSrcTrade from './data/ExtremeSrcTrade.json';
import ExtremeTrgTrade from './data/ExtremeTrgTrade.json';

const tests = [
    ...ArbitraryTrade,
    ...EthUsdcTrade,
    ...ExtremeSrcTrade,
    ...ExtremeTrgTrade,
];

describe('Strategies', () => {
    let contract: TestStrategies;

    before(async () => {
        contract = await Contracts.TestStrategies.deploy();
    });

    for (const [index, test] of tests.entries()) {
        it(`test ${index + 1} out of ${tests.length}`, async () => {
            const order = encodeOrder({
                liquidity: new Decimal(test.liquidity),
                lowestRate: new Decimal(test.lowestRate),
                highestRate: new Decimal(test.highestRate),
                marginalRate: new Decimal(test.marginalRate)
            });
            const amount = BigNumber.from(test.inputAmount);
            const tradeRPC = (contract as any)[`tradeBy${test.tradeBy}`](order, amount);
            const expected = BigNumber.from(test.implReturn);
            expect(await tradeRPC).to.eq(expected);
        });
    };
});
