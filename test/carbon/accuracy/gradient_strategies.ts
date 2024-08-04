import Contracts, { TestTrade } from '../../../components/Contracts';

import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumber } from 'ethers';

Decimal.set({precision: 100, rounding: Decimal.ROUND_HALF_DOWN});

const BnToDec = (x: BigNumber) => new Decimal(x.toString());
const DecToBn = (x: Decimal) => BigNumber.from(x.toFixed());

const bitLength = (value: BigNumber) => {
    return value.gt(0) ? Decimal.log2(value.toString()).add(1).floor().toNumber() : 0;
};

const encode = (value: Decimal, shift: number) => {
    const factor = new Decimal(2).pow(shift);
    const data = DecToBn(value.mul(factor).floor());
    const length = bitLength(data.shr(shift));
    const integer = data.shr(length).shl(length);
    const exponent = bitLength(integer.shr(shift));
    const mantissa = integer.shr(exponent);
    return BigNumber.from(exponent).shl(shift).or(mantissa);
};

const initialRateEncode = (value: Decimal) => {
    return encode(value.sqrt(), 48);
};

const multiFactorEncode = (value: Decimal) => {
    return encode(value, 24);
};

function assertAlmostEqual(actual: Decimal, expected: Decimal, maxAbsoluteError: string, maxRelativeError: string) {
    if (!actual.eq(expected)) {
        const absoluteError = actual.sub(expected).abs();
        const relativeError = actual.div(expected).sub(1).abs();
        const ok = absoluteError.lte(maxAbsoluteError) || relativeError.lte(maxRelativeError);
        expect(ok,
            `\n- actual        = ${actual}` +
            `\n- expected      = ${expected}` +
            `\n- absoluteError = ${absoluteError.toFixed()}` +
            `\n- relativeError = ${relativeError.toFixed()}`
        );
    }
}

describe('Gradient strategies accuracy stress test', () => {
    let contract: TestTrade;

    before(async () => {
        contract = await Contracts.TestTrade.deploy();
    });

    for (const gradientType of [0, 1, 2, 3]) {
        for (let initialRate = new Decimal(10); initialRate.lt(100); initialRate = initialRate.add(10.1)) {
            for (let multiFactor = new Decimal(0.001); multiFactor.lt(0.01); multiFactor = multiFactor.add(0.0011)) {
                for (let timeElapsed = new Decimal(10); timeElapsed.lt(100); timeElapsed = timeElapsed.add(10)) {
                    it(`gradientType, initialRate, multiFactor, timeElapsed = ${[gradientType, initialRate, multiFactor, timeElapsed]}`, async () => {
                        let expected = new Decimal(0);
                        switch (gradientType) {
                            case 0: expected = initialRate.mul(multiFactor.mul(timeElapsed).add(1)); break;
                            case 1: expected = initialRate.div(multiFactor.mul(timeElapsed).add(1)); break;
                            case 2: expected = initialRate.mul(multiFactor.mul(timeElapsed).exp()); break;
                            case 3: expected = initialRate.div(multiFactor.mul(timeElapsed).exp()); break;
                        }
                        const r = initialRateEncode(initialRate);
                        const m = multiFactorEncode(multiFactor);
                        const t = DecToBn(timeElapsed);
                        const x = await contract.calcCurrentRate(gradientType, r, m, t);
                        const actual = BnToDec(x[0]).div(BnToDec(x[1]));
                        switch (gradientType) {
                            case 0: assertAlmostEqual(actual, expected, "0", "0"); break;
                            case 1: assertAlmostEqual(actual, expected, "0", "0"); break;
                            case 2: assertAlmostEqual(actual, expected, "0", "0"); break;
                            case 3: assertAlmostEqual(actual, expected, "0", "0"); break;
                        }
                    });
                }
            }
        }
    }
});
