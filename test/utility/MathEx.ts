import Contracts, { TestMathEx } from '../../components/Contracts';
import { expect } from 'chai';
import { BigNumber } from 'ethers';

const MAX_UINT256 = BigNumber.from(2).pow(256).sub(1);

const mulDivFuncs = {
    mulDivF: (x: BigNumber, y: BigNumber, z: BigNumber) => x.mul(y).div(z),
    mulDivC: (x: BigNumber, y: BigNumber, z: BigNumber) => x.mul(y).add(z).sub(1).div(z)
};

describe('MathEx', () => {
    let mathContract: TestMathEx;

    before(async () => {
        mathContract = await Contracts.TestMathEx.deploy();
    });

    const testMulDivAndMinFactor = (x: BigNumber, y: BigNumber, z: BigNumber) => {
        for (const funcName in mulDivFuncs) {
            it(`${funcName}(${x}, ${y}, ${z})`, async () => {
                const expectedFunc = (mulDivFuncs as any)[funcName];
                const actualFunc = (mathContract as any)[funcName];
                const expected = expectedFunc(x, y, z);
                if (expected.lte(MAX_UINT256)) {
                    const actual = await actualFunc(x, y, z);
                    expect(actual).to.equal(expected);
                } else {
                    await expect(actualFunc(x, y, z)).to.be.revertedWithError('Overflow');
                }
            });
        }

        const tuples = [
            [x, y],
            [x, z],
            [y, z],
            [x, y.add(z)],
            [x.add(z), y],
            [x.add(z), y.add(z)]
        ];
        const values = tuples.filter((tuple) => tuple.every((value) => value.lte(MAX_UINT256)));
        for (const [x, y] of values) {
            it(`minFactor(${x}, ${y})`, async () => {
                const actual = await mathContract.minFactor(x, y);
                expect(mulDivFuncs.mulDivC(x, y, actual)).to.be.lte(MAX_UINT256);
                if (actual.gt(1)) {
                    expect(mulDivFuncs.mulDivC(x, y, actual.sub(1))).to.be.gt(MAX_UINT256);
                }
            });
        }
    };

    describe('quick tests', () => {
        for (const px of [128, 192, 256]) {
            for (const py of [128, 192, 256]) {
                for (const pz of [128, 192, 256]) {
                    for (const ax of [3, 5, 7]) {
                        for (const ay of [3, 5, 7]) {
                            for (const az of [3, 5, 7]) {
                                const x = BigNumber.from(2).pow(px).div(ax);
                                const y = BigNumber.from(2).pow(py).div(ay);
                                const z = BigNumber.from(2).pow(pz).div(az);
                                testMulDivAndMinFactor(x, y, z);
                            }
                        }
                    }
                }
            }
        }
    });

    describe('@stress tests', () => {
        for (const px of [0, 64, 128, 192, 255, 256]) {
            for (const py of [0, 64, 128, 192, 255, 256]) {
                for (const pz of [1, 64, 128, 192, 255, 256]) {
                    for (const ax of px < 256 ? [-1, 0, +1] : [-1]) {
                        for (const ay of py < 256 ? [-1, 0, +1] : [-1]) {
                            for (const az of pz < 256 ? [-1, 0, +1] : [-1]) {
                                const x = BigNumber.from(2).pow(px).add(ax);
                                const y = BigNumber.from(2).pow(py).add(ay);
                                const z = BigNumber.from(2).pow(pz).add(az);
                                testMulDivAndMinFactor(x, y, z);
                            }
                        }
                    }
                }
            }
        }

        for (const px of [64, 128, 192, 256]) {
            for (const py of [64, 128, 192, 256]) {
                for (const pz of [64, 128, 192, 256]) {
                    for (const ax of [BigNumber.from(2).pow(px >> 1), 1]) {
                        for (const ay of [BigNumber.from(2).pow(py >> 1), 1]) {
                            for (const az of [BigNumber.from(2).pow(pz >> 1), 1]) {
                                const x = BigNumber.from(2).pow(px).sub(ax);
                                const y = BigNumber.from(2).pow(py).sub(ay);
                                const z = BigNumber.from(2).pow(pz).sub(az);
                                testMulDivAndMinFactor(x, y, z);
                            }
                        }
                    }
                }
            }
        }

        for (const px of [128, 192, 256]) {
            for (const py of [128, 192, 256]) {
                for (const pz of [128, 192, 256]) {
                    for (const ax of [3, 5, 7]) {
                        for (const ay of [3, 5, 7]) {
                            for (const az of [3, 5, 7]) {
                                const x = BigNumber.from(2).pow(px).div(ax);
                                const y = BigNumber.from(2).pow(py).div(ay);
                                const z = BigNumber.from(2).pow(pz).div(az);
                                testMulDivAndMinFactor(x, y, z);
                            }
                        }
                    }
                }
            }
        }
    });
});
