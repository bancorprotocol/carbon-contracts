import Contracts, { TestTrade } from '../../../components/Contracts';

import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumber } from 'ethers';

let contract: TestTrade;

const R_SHIFT = 48;
const M_SHIFT = 24;

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

function decode(value: BigNumber, shift: number) {
    const mantissa = value.mask(shift);
    const exponent = value.shr(shift).toNumber();
    const data = BnToDec(mantissa.shl(exponent));
    const factor = new Decimal(2).pow(shift);
    return data.div(factor)
}

function initialRateEncoded(value: Decimal) {
    return encode(value.sqrt(), R_SHIFT);
}

function initialRateDecoded(value: BigNumber) {
    return decode(value, R_SHIFT).pow(2);
}

function multiFactorEncoded(value: Decimal) {
    return encode(value.mul(new Decimal(2).pow(M_SHIFT)), M_SHIFT);
}

function multiFactorDecoded(value: BigNumber) {
    return decode(value, M_SHIFT).div(new Decimal(2).pow(M_SHIFT));
}

function expectedCurrentRate(
    gradientType: number,
    initialRate: Decimal,
    multiFactor: Decimal,
    timeElapsed: Decimal
) {
    switch (gradientType) {
        case 0: return initialRate.mul(multiFactor.mul(timeElapsed).add(1));
        case 1: return initialRate.div(multiFactor.mul(timeElapsed).add(1));
        case 2: return initialRate.mul(multiFactor.mul(timeElapsed).exp());
        case 3: return initialRate.div(multiFactor.mul(timeElapsed).exp());
    }
    throw new Error(`Invalid gradientType ${gradientType}`);
}

async function actualCurrentRate(
    gradientType: number,
    initialRate: BigNumber,
    multiFactor: BigNumber,
    timeElapsed: BigNumber
) {
    const currentRate = await contract.calcCurrentRate(gradientType, initialRate, multiFactor, timeElapsed);
    return BnToDec(currentRate[0]).div(BnToDec(currentRate[1]));
}

function testCurrentRate(
    gradientType: number,
    initialRate: Decimal,
    multiFactor: Decimal,
    timeElapsed: Decimal,
    maxError: string
) {
    it(`testCurrentRate: gradientType, initialRate, multiFactor, timeElapsed = ${[gradientType, initialRate, multiFactor, timeElapsed]}`, async () => {
        const rEncoded = initialRateEncoded(initialRate);
        const mEncoded = multiFactorEncoded(multiFactor);
        const rDecoded = initialRateDecoded(rEncoded);
        const mDecoded = multiFactorDecoded(mEncoded);
        const expected = expectedCurrentRate(gradientType, rDecoded, mDecoded, timeElapsed);
        const actual = await actualCurrentRate(gradientType, rEncoded, mEncoded, DecToBn(timeElapsed));
        if (!actual.eq(expected)) {
            const error = actual.div(expected).sub(1).abs();
            expect(error.lte(maxError)).to.be.equal(
                true,
                `\n- expected = ${expected.toFixed()}` +
                `\n- actual   = ${actual.toFixed()}` +
                `\n- error    = ${error.toFixed()}`
            );
        }
    });
}

function testConfiguration(
    paramName: string,
    paramValue: Decimal,
    encodeFunc: (value: Decimal) => BigNumber,
    decodeFunc: (value: BigNumber) => Decimal,
    maxAbsoluteError: string,
    maxRelativeError: string
) {
    it(`testConfiguration: ${paramName} = ${paramValue}`, async () => {
        const expected = paramValue;
        const actual = decodeFunc(encodeFunc(paramValue));
        if (!actual.eq(expected)) {
            expect(actual.lt(expected)).to.be.equal(
                true,
                `\n- expected = ${expected.toFixed()}` +
                `\n- actual   = ${actual.toFixed()}`
            );
            const absoluteError = actual.sub(expected).abs();
            const relativeError = actual.div(expected).sub(1).abs();
            expect(absoluteError.lte(maxAbsoluteError) || relativeError.lte(maxRelativeError)).to.be.equal(
                true,
                `\n- expected      = ${expected.toFixed()}` +
                `\n- actual        = ${actual.toFixed()}` +
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
                testCurrentRate(0, initialRate, multiFactor, timeElapsed, "0");
                testCurrentRate(1, initialRate, multiFactor, timeElapsed, "0");
                testCurrentRate(2, initialRate, multiFactor, timeElapsed, "0.00000000000000000000000000000000000002");
                testCurrentRate(3, initialRate, multiFactor, timeElapsed, "0.00000000000000000000000000000000000002");
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
                testCurrentRate(0, initialRate, multiFactor, timeElapsed, "0");
                testCurrentRate(1, initialRate, multiFactor, timeElapsed, "0");
                testCurrentRate(2, initialRate, multiFactor, timeElapsed, "0.000000000000000000000000000000000002");
                testCurrentRate(3, initialRate, multiFactor, timeElapsed, "0.000000000000000000000000000000000002");
            }
        }
    }

    for (let a = 1; a <= 100; a++) {
        const initialRate = new Decimal(a).mul(1234.5678);
        testConfiguration("initialRate", initialRate, initialRateEncoded, initialRateDecoded, "0", "0.00000000000002");
    }

    for (let b = 1; b <= 100; b++) {
        const multiFactor = new Decimal(b).mul(0.00001234);
        testConfiguration("multiFactor", multiFactor, multiFactorEncoded, multiFactorDecoded, "0", "0.0000002");
    }

    for (let a = -28; a <= 28; a++) {
        const initialRate = new Decimal(10).pow(a);
        testConfiguration("initialRate", initialRate, initialRateEncoded, initialRateDecoded, "0.0000000000000005", "0.00000000000002");
    }

    for (let b = -14; b <= -1; b++) {
        const multiFactor = new Decimal(10).pow(b);
        testConfiguration("multiFactor", multiFactor, multiFactorEncoded, multiFactorDecoded, "0.000000000000004", "0.0000002");
    }
});
