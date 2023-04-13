import Contracts, { CarbonController, TestERC20Burnable } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { createSystem, createTestToken } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { expect } from 'chai';

const sortTokens = (token0: string, token1: string): string[] => {
    return token0 < token1 ? [token0, token1] : [token1, token0];
};

describe('Pairs', () => {
    let carbonController: CarbonController;
    let token0: TestERC20Burnable;
    let token1: TestERC20Burnable;
    let pair: any;

    beforeEach(async () => {
        ({ carbonController } = await createSystem());
        token0 = await createTestToken();
        token1 = await createTestToken();
        pair = { id: 1, token0: token0.address, token1: token1.address };
    });

    shouldHaveGap('Pairs', '_lastPairId');

    describe('pair creation', () => {
        it('reverts for non valid addresses', async () => {
            const permutations = [
                { token0: token0.address, token1: ZERO_ADDRESS },
                { token0: ZERO_ADDRESS, token1: token1.address },
                { token0: ZERO_ADDRESS, token1: ZERO_ADDRESS }
            ];

            for (const pair of permutations) {
                await expect(carbonController.createPair(pair.token0, pair.token1)).to.be.revertedWithError(
                    'InvalidAddress'
                );
            }
        });

        it('should revert when addresses are identical', async () => {
            const pair = { token0: token0.address, token1: token0.address };
            await expect(carbonController.createPair(pair.token0, pair.token1)).to.be.revertedWithError(
                'IdenticalAddresses'
            );
        });

        it('should revert when pair already exist', async () => {
            await carbonController.createPair(pair.token0, pair.token1);
            await expect(carbonController.createPair(pair.token0, pair.token1)).to.be.revertedWithError(
                'PairAlreadyExists'
            );
        });

        it('should create a pair', async () => {
            const res = await carbonController.createPair(pair.token0, pair.token1);
            const tokens = [pair.token0, pair.token1];
            const pairs = await carbonController.pairs();
            const sortedTokens = sortTokens(tokens[0], tokens[1]);
            await expect(res).to.emit(carbonController, 'PairCreated').withArgs(1, sortedTokens[0], sortedTokens[1]);
            await expect(pairs).to.deep.equal([sortedTokens]);
        });

        it('should increase pairId', async () => {
            await carbonController.createPair(token0.address, token1.address);

            const token2 = await createTestToken();
            const token3 = await createTestToken();

            const res = await carbonController.createPair(token2.address, token3.address);
            const tokens = sortTokens(token2.address, token3.address);

            await expect(res).to.emit(carbonController, 'PairCreated').withArgs(2, tokens[0], tokens[1]);
        });

        it('sorts the tokens by address value size, smaller first', async () => {
            const sortedTokens =
                token0.address < token1.address ? [token0.address, token1.address] : [token1.address, token0.address];
            const res = await carbonController.createPair(sortedTokens[1], sortedTokens[0]);
            await expect(res).to.emit(carbonController, 'PairCreated').withArgs(1, sortedTokens[0], sortedTokens[1]);
        });
    });

    it('gets a pair matching the provided tokens', async () => {
        await carbonController.createPair(pair.token0, pair.token1);
        const tokens = sortTokens(pair.token0, pair.token1);

        const _pair = await carbonController.pair(pair.token0, pair.token1);
        expect(_pair.id.toNumber()).to.eq(1);
        expect(_pair.tokens[0]).to.eq(tokens[0]);
        expect(_pair.tokens[1]).to.eq(tokens[1]);
    });

    it('gets a pair matching the provided unsorted tokens', async () => {
        const tokens = sortTokens(pair.token0, pair.token1);
        await carbonController.createPair(tokens[0], tokens[1]);
        const _pair = await carbonController.pair(tokens[1], tokens[0]);
        expect(_pair.id.toNumber()).to.eq(1);
        expect(_pair.tokens[0]).to.eq(tokens[0]);
        expect(_pair.tokens[1]).to.eq(tokens[1]);
    });

    it('lists all supported tokens', async () => {
        await carbonController.createPair(pair.token0, pair.token1);
        const pairs = await carbonController.pairs();
        const tokens = sortTokens(pair.token0, pair.token1);
        expect(pairs).to.deep.eq([[tokens[0], tokens[1]]]);
    });

    describe('_pairById unit tests', () => {
        it('reverts when trying to fetch a pair by an id that does not exist', async () => {
            const testPairs = await Contracts.TestPairs.deploy();
            await testPairs.testCreatePair(token0.address, token1.address);
            await expect(testPairs.testPairById(2)).to.be.revertedWithError('PairDoesNotExist');
        });
    });
});
