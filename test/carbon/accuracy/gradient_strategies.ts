import Contracts, { TestTrade } from '../../../components/Contracts';

import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumber } from 'ethers';

let contract: TestTrade;

const R_SHIFT = 48;
const M_SHIFT = 24;

const ONE = new Decimal(1);
const TWO = new Decimal(2);

const EXP_ONE = TWO.pow(127);
const EXP_MAX = EXP_ONE.mul(TWO.ln()).ceil().mul(129);

const BnToDec = (x: BigNumber) => new Decimal(x.toString());
const DecToBn = (x: Decimal) => BigNumber.from(x.toFixed());

function bitLength(value: BigNumber) {
    return value.gt(0) ? Decimal.log2(value.toString()).add(1).floor().toNumber() : 0;
}

function encode(value: Decimal, shift: number) {
    const factor = TWO.pow(shift);
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
    const factor = TWO.pow(shift);
    return data.div(factor);
}

function initialRateEncoded(value: Decimal) {
    return encode(value.sqrt(), R_SHIFT);
}

function initialRateDecoded(value: BigNumber) {
    return decode(value, R_SHIFT).pow(2);
}

function multiFactorEncoded(value: Decimal) {
    return encode(value.mul(TWO.pow(M_SHIFT)), M_SHIFT);
}

function multiFactorDecoded(value: BigNumber) {
    return decode(value, M_SHIFT).div(TWO.pow(M_SHIFT));
}

function expectedCurrentRate(
    gradientType: number,
    initialRate: Decimal,
    multiFactor: Decimal,
    timeElapsed: Decimal
) {
    switch (gradientType) {
        case 0: return initialRate.mul(ONE.add(multiFactor.mul(timeElapsed)));
        case 1: return initialRate.mul(ONE.sub(multiFactor.mul(timeElapsed)));
        case 2: return initialRate.div(ONE.sub(multiFactor.mul(timeElapsed)));
        case 3: return initialRate.div(ONE.add(multiFactor.mul(timeElapsed)));
        case 4: return initialRate.mul(multiFactor.mul(timeElapsed).exp());
        case 5: return initialRate.div(multiFactor.mul(timeElapsed).exp());
    }
    throw new Error(`Invalid gradientType ${gradientType}`);
}

function testCurrentRate(
    gradientType: number,
    initialRate: Decimal,
    multiFactor: Decimal,
    timeElapsed: Decimal,
    maxError: string
) {
    it(`testCurrentRate: gradientType,initialRate,multiFactor,timeElapsed = ${[gradientType, initialRate, multiFactor, timeElapsed]}`, async () => {
        const rEncoded = initialRateEncoded(initialRate);
        const mEncoded = multiFactorEncoded(multiFactor);
        const rDecoded = initialRateDecoded(rEncoded);
        const mDecoded = multiFactorDecoded(mEncoded);
        const expected = expectedCurrentRate(gradientType, rDecoded, mDecoded, timeElapsed);
        const funcCall = contract.calcCurrentRate(gradientType, rEncoded, mEncoded, DecToBn(timeElapsed));
        if (expected.isFinite() && expected.isPositive()) {
            const retVal = await funcCall;
            const actual = BnToDec(retVal[0]).div(BnToDec(retVal[1]));
            if (!actual.eq(expected)) {
                const error = actual.div(expected).sub(1).abs();
                expect(error.lte(maxError)).to.be.equal(
                    true,
                    `\n- expected = ${expected.toFixed()}` +
                    `\n- actual   = ${actual.toFixed()}` +
                    `\n- error    = ${error.toFixed()}`
                );
            }
        } else {
            await expect(funcCall).to.be.revertedWithError('InvalidRate');
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

function testExpNative(n: number, d: number, maxError: string) {
    it(`testExpNative(${n} / ${d})`, async () => {
        const x = EXP_ONE.mul(n).div(d).floor();
        await testExp(x, maxError);
    });
}

function testExpScaled(x: Decimal, maxError: string) {
    it(`testExpScaled(${x.toHex()})`, async () => {
        await testExp(x, maxError);
    });
}

async function testExp(x: Decimal, maxError: string) {
    if (x.lt(EXP_MAX)) {
        const actual = BnToDec(await contract.exp(DecToBn(x)));
        const expected = x.div(EXP_ONE).exp().mul(EXP_ONE);
        if (!actual.eq(expected)) {
            expect(actual.lt(expected)).to.be.equal(
                true,
                `\n- expected = ${expected.toFixed()}` +
                `\n- actual   = ${actual.toFixed()}`
            );
            const error = actual.div(expected).sub(1).abs();
            expect(error.lte(maxError)).to.be.equal(
                true,
                `\n- expected = ${expected.toFixed()}` +
                `\n- actual   = ${actual.toFixed()}` +
                `\n- error    = ${error.toFixed()}`
            );
        }
    } else {
        await expect(contract.exp(DecToBn(x))).to.revertedWithError('ExpOverflow');
    }
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
                testCurrentRate(0, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(1, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(2, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(3, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(4, initialRate, multiFactor, timeElapsed, '0.00000000000000000000000000000000000002');
                testCurrentRate(5, initialRate, multiFactor, timeElapsed, '0.00000000000000000000000000000000000002');
            }
        }
    }

    for (let a = -27; a <= 27; a++) {
        for (let b = -14; b <= -1; b++) {
            for (let c = 1; c <= 10; c++) {
                const initialRate = new Decimal(10).pow(a);
                const multiFactor = new Decimal(10).pow(b);
                const timeElapsed = Decimal.min(
                    TWO.pow(4).div(multiFactor).sub(1).ceil(),
                    TWO.pow(25).sub(1)
                ).mul(c).div(10).ceil();
                testCurrentRate(0, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(1, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(2, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(3, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(4, initialRate, multiFactor, timeElapsed, '0.00000000000000000000000000000000000006');
                testCurrentRate(5, initialRate, multiFactor, timeElapsed, '0.00000000000000000000000000000000000006');
            }
        }
    }

    for (const a of [-27, -10, 0, 10, 27]) {
        for (const b of [-14, -9, -6, -1]) {
            for (const c of [1, 4, 7, 10]) {
                const initialRate = new Decimal(10).pow(a);
                const multiFactor = new Decimal(10).pow(b);
                const timeElapsed = Decimal.min(
                    EXP_MAX.div(EXP_ONE).div(multiFactor).sub(1).ceil(),
                    TWO.pow(25).sub(1)
                ).mul(c).div(10).ceil();
                testCurrentRate(0, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(1, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(2, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(3, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(4, initialRate, multiFactor, timeElapsed, '0.000000000004');
                testCurrentRate(5, initialRate, multiFactor, timeElapsed, '0.0000000000000000000000000000000000003');
            }
        }
    }

    for (const a of [-27, -10, 0, 10, 27]) {
        for (const b of [-14, -9, -6, -1]) {
            for (const c of [19, 24, 29]) {
                const initialRate = new Decimal(10).pow(a);
                const multiFactor = new Decimal(10).pow(b);
                const timeElapsed = new Decimal(2).pow(c).sub(1);
                testCurrentRate(0, initialRate, multiFactor, timeElapsed, '0.0000000000000000000000000000000000000000003');
                testCurrentRate(1, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(2, initialRate, multiFactor, timeElapsed, '0');
                testCurrentRate(3, initialRate, multiFactor, timeElapsed, '0');
            }
        }
    }

    for (let a = 1; a <= 100; a++) {
        const initialRate = new Decimal(a).mul(1234.5678);
        testConfiguration('initialRate', initialRate, initialRateEncoded, initialRateDecoded, '0', '0.00000000000002');
    }

    for (let b = 1; b <= 100; b++) {
        const multiFactor = new Decimal(b).mul(0.00001234);
        testConfiguration('multiFactor', multiFactor, multiFactorEncoded, multiFactorDecoded, '0', '0.0000002');
    }

    for (let a = -28; a <= 28; a++) {
        const initialRate = new Decimal(10).pow(a);
        testConfiguration('initialRate', initialRate, initialRateEncoded, initialRateDecoded, '0.0000000000000005', '0.00000000000002');
    }

    for (let b = -14; b <= -1; b++) {
        const multiFactor = new Decimal(10).pow(b);
        testConfiguration('multiFactor', multiFactor, multiFactorEncoded, multiFactorDecoded, '0.000000000000004', '0.00000007');
    }

    for (let n = 1; n <= 100; n++) {
        for (let d = 1; d <= 100; d++) {
            testExpNative(n, d, '0.0000000000000000000000000000000000003');
        }
    }

    for (let d = 1000; d <= 1000000000; d *= 10) {
        for (let n = d - 10; n <= d + 10; n++) {
            testExpNative(n, d, '0.00000000000000000000000000000000000002');
        }
    }

    for (let n = 1; n < 1000; n++) {
        testExpNative(n, 1000, '0.00000000000000000000000000000000000002');
    }

    for (let d = 1; d < 1000; d++) {
        testExpNative(1, d, '0.00000000000000000000000000000000000002');
    }

    for (let i = 0; i < 10; i++) {
        for (const j of [-1, 0, +1]) {
            testExpScaled(EXP_ONE.mul(TWO.pow(i + 1).ln()).floor().add(j), '0.00000000000000000000000000000000000003');
        }
    }

    for (let i = 0; i < 10; i++) {
        for (const j of [-1, 0, +1]) {
            testExpScaled(EXP_ONE.mul(TWO.ln().pow(i + 2)).floor().add(j), '0.00000000000000000000000000000000000002');
        }
    }

    for (let i = 0; i < 10; i++) {
        for (const j of [-1, 0, +1]) {
            testExpScaled(EXP_ONE.mul(TWO.pow(i - 3)).add(j), '0.0000000000000000000000000000000000003');
        }
    }

    for (let i = 0; i < 10; i++) {
        testExpScaled(EXP_MAX.add(i - 10), '0.0000000000000000000000000000000000003');
    }
});
