import Contracts, { TestExpDecayMath } from '../../components/Contracts';
import { toWei } from '../../utils/Types';
import { duration } from '../helpers/Time';
import { Relation } from '../matchers';
import { expect } from 'chai';
import Decimal from 'decimal.js';
import { BigNumberish } from 'ethers';

const { seconds, days, minutes, hours, years } = duration;

describe('ExpDecayMath', () => {
    let expDecayMath: TestExpDecayMath;
    const ONE = new Decimal(1);
    const TWO = new Decimal(2);
    const MAX = new Decimal(128);

    before(async () => {
        expDecayMath = await Contracts.TestExpDecayMath.deploy();
    });

    const calcExpDecay = (ethAmount: BigNumberish, timeElapsed: number, halfLife: number) => {
        it(`calcExpDecay(${ethAmount}, ${timeElapsed}, ${halfLife})`, async () => {
            const f = new Decimal(timeElapsed).div(halfLife);
            if (f.lte(MAX)) {
                const f = new Decimal(timeElapsed).div(halfLife);
                // actual amount calculated in solidity
                const actual = await expDecayMath.calcExpDecay(ethAmount, timeElapsed, halfLife);
                // expected amount calculated using ts Decimal lib
                const expected = new Decimal(ethAmount.toString()).mul(ONE.div(TWO.pow(f)));
                expect(actual).to.almostEqual(expected, {
                    maxAbsoluteError: new Decimal(1),
                    relation: Relation.LesserOrEqual
                });
            } else {
                await expect(expDecayMath.calcExpDecay(ethAmount, timeElapsed, halfLife)).to.revertedWithError(
                    'panic code 0x11'
                );
            }
        });

        // verify that after half-life has elapsed, we get half of the amount
        it(`calcExpDecay(${ethAmount}, ${halfLife}, ${halfLife})`, async () => {
            const actual = await expDecayMath.calcExpDecay(ethAmount, halfLife, halfLife);
            const expected = new Decimal(ethAmount.toString()).div(TWO);
            expect(actual).to.equal(expected);
        });
    };

    describe('regular tests', () => {
        for (const ethAmount of [50_000_000, toWei(1), toWei(40_000_000)]) {
            for (const timeElapsed of [
                0,
                seconds(1),
                seconds(10),
                minutes(1),
                minutes(10),
                hours(1),
                hours(10),
                days(1),
                days(2),
                days(5),
                days(10),
                days(100),
                years(1),
                years(2)
            ]) {
                for (const halfLife of [days(2), days(5), days(10), days(20)]) {
                    calcExpDecay(ethAmount, timeElapsed, halfLife);
                }
            }
        }
    });

    describe('@stress tests', () => {
        for (const ethAmount of [
            40_000_000,
            400_000_000,
            4_000_000_000,
            toWei(50_000_000),
            toWei(500_000_000),
            toWei(5_000_000_000)
        ]) {
            for (let secondsNum = 0; secondsNum < 5; secondsNum++) {
                for (let minutesNum = 0; minutesNum < 5; minutesNum++) {
                    for (let hoursNum = 0; hoursNum < 5; hoursNum++) {
                        for (let daysNum = 0; daysNum < 5; daysNum++) {
                            for (let yearsNum = 0; yearsNum < 5; yearsNum++) {
                                for (const halfLife of [
                                    days(1),
                                    days(30),
                                    years(0.5),
                                    years(1),
                                    years(1.5),
                                    years(2)
                                ]) {
                                    calcExpDecay(
                                        ethAmount,
                                        seconds(secondsNum) +
                                            minutes(minutesNum) +
                                            hours(hoursNum) +
                                            days(daysNum) +
                                            years(yearsNum),
                                        halfLife
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }
    });
});
