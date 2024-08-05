import Contracts, { TestTrade } from '../../../components/Contracts';

import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumber } from 'ethers';

let contract: TestTrade;

Decimal.set({precision: 100, rounding: Decimal.ROUND_HALF_DOWN});

const BnToDec = (x: BigNumber) => new Decimal(x.toString());
const DecToBn = (x: Decimal) => BigNumber.from(x.toFixed());

function bitLength(value: BigNumber) {
    return value.gt(0) ? Decimal.log2(value.toString()).add(1).floor().toNumber() : 0;
}

function encode(value: Decimal, shift: number) {
    const factor = new Decimal(2).pow(shift);
    const data = DecToBn(value.mul(factor).floor());
    const length = bitLength(data.shr(shift));
    const integer = data.shr(length).shl(length);
    const exponent = bitLength(integer.shr(shift));
    const mantissa = integer.shr(exponent);
    return BigNumber.from(exponent).shl(shift).or(mantissa);
}

function initialRateEncoded(value: Decimal) {
    return encode(value.sqrt(), 48);
}

function multiFactorEncoded(value: Decimal) {
    return encode(value.mul(new Decimal(2).pow(24)), 24);
}

function test(
    gradientType: number,
    initialRate: Decimal,
    multiFactor: Decimal,
    timeElapsed: Decimal,
    maxAbsoluteError: string,
    maxRelativeError: string
) {
    it(`gradientType, initialRate, multiFactor, timeElapsed = ${[gradientType, initialRate, multiFactor, timeElapsed]}`, async () => {
        let expected = new Decimal(0);
        switch (gradientType) {
            case 0: expected = initialRate.mul(multiFactor.mul(timeElapsed).add(1)); break;
            case 1: expected = initialRate.div(multiFactor.mul(timeElapsed).add(1)); break;
            case 2: expected = initialRate.mul(multiFactor.mul(timeElapsed).exp()); break;
            case 3: expected = initialRate.div(multiFactor.mul(timeElapsed).exp()); break;
        }
        const r = initialRateEncoded(initialRate);
        const m = multiFactorEncoded(multiFactor);
        const t = DecToBn(timeElapsed);
        const currentRate = await contract.calcCurrentRate(gradientType, r, m, t);
        const actual = BnToDec(currentRate[0]).div(BnToDec(currentRate[1]));
        if (!actual.eq(expected)) {
            const absoluteError = actual.sub(expected).abs();
            const relativeError = actual.div(expected).sub(1).abs();
            expect(absoluteError.lte(maxAbsoluteError) || relativeError.lte(maxRelativeError)).to.be.equal(
                true,
                `\n- actual        = ${actual}` +
                `\n- expected      = ${expected}` +
                `\n- absoluteError = ${absoluteError.toFixed()}` +
                `\n- relativeError = ${relativeError.toFixed()}`
            );
        }
    });
}

describe('Gradient strategies accuracy stress test', () => {
    before(async () => {
        contract = await Contracts.TestTrade.deploy();
    });

    for (let a = 1; a <= 10; a++) {
        for (let b = 1; b <= 10; b++) {
            for (let c = 1; c <= 10; c++) {
                const initialRate = new Decimal(a).mul(1234.5678);
                const multiFactor = new Decimal(b).mul(0.00001234);
                const timeElapsed = new Decimal(c).mul(3600);
                test(0, initialRate, multiFactor, timeElapsed, "0", "0.000000052");
                test(1, initialRate, multiFactor, timeElapsed, "0", "0.000000052");
                test(2, initialRate, multiFactor, timeElapsed, "0", "0.000000225");
                test(3, initialRate, multiFactor, timeElapsed, "0", "0.000000225");
            }
        }
    }

    for (let a = -27; a <= 27; a++) {
        for (let b = -14; b <= -1; b++) {
            for (let c = 1; c <= 10; c++) {
                const initialRate = new Decimal(10).pow(a);
                const multiFactor = new Decimal(10).pow(b);
                const timeElapsed = Decimal.min(
                    new Decimal(16).div(multiFactor).sub(1).ceil(),
                    new Decimal(2).pow(25).sub(1)
                ).mul(c).div(10).ceil();
                test(0, initialRate, multiFactor, timeElapsed, "0.00000000000000000001", "0.00000012");
                test(1, initialRate, multiFactor, timeElapsed, "0.00000000000000000001", "0.00000012");
                test(2, initialRate, multiFactor, timeElapsed, "0.00000000000000007140", "0.00000165");
                test(3, initialRate, multiFactor, timeElapsed, "0.00000000000000007140", "0.00000165");
            }
        }
    }
});
