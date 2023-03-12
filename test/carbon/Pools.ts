import Contracts, { CarbonController, TestERC20Burnable } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { createSystem, createTestToken } from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { expect } from 'chai';

const sortTokens = (token0: string, token1: string): string[] => {
    return token0 < token1 ? [token0, token1] : [token1, token0];
};

describe('Pools', () => {
    let carbonController: CarbonController;
    let token0: TestERC20Burnable;
    let token1: TestERC20Burnable;
    let pool: any;

    beforeEach(async () => {
        ({ carbonController } = await createSystem());
        token0 = await createTestToken();
        token1 = await createTestToken();
        pool = { id: 1, token0: token0.address, token1: token1.address };
    });

    shouldHaveGap('Pools', '_lastPoolId');

    describe('pool creation', () => {
        it('reverts for non valid addresses', async () => {
            const permutations = [
                { token0: token0.address, token1: ZERO_ADDRESS },
                { token0: ZERO_ADDRESS, token1: token1.address },
                { token0: ZERO_ADDRESS, token1: ZERO_ADDRESS }
            ];

            for (const pool of permutations) {
                await expect(carbonController.createPool(pool.token0, pool.token1)).to.be.revertedWithError(
                    'InvalidAddress'
                );
            }
        });

        it('should revert when addresses are identical', async () => {
            const pool = { token0: token0.address, token1: token0.address };
            await expect(carbonController.createPool(pool.token0, pool.token1)).to.be.revertedWithError(
                'IdenticalAddresses'
            );
        });

        it('should revert when pool already exist', async () => {
            await carbonController.createPool(pool.token0, pool.token1);
            await expect(carbonController.createPool(pool.token0, pool.token1)).to.be.revertedWithError(
                'PoolAlreadyExists'
            );
        });

        it('should create a pool', async () => {
            const res = await carbonController.createPool(pool.token0, pool.token1);
            const tokens = [pool.token0, pool.token1];
            const pairs = await carbonController.pairs();

            await expect(res).to.emit(carbonController, 'PoolCreated').withArgs(1, pool.token0, pool.token1);
            await expect(pairs).to.deep.equal([tokens]);
        });

        it('should increase pairId', async () => {
            await carbonController.createPool(token0.address, token1.address);

            const token2 = await createTestToken();
            const token3 = await createTestToken();

            const res = await carbonController.createPool(token2.address, token3.address);
            const tokens = [token2.address, token3.address];

            await expect(res).to.emit(carbonController, 'PoolCreated').withArgs(2, tokens[0], tokens[1]);
        });

        it('sorts the tokens by address value size, smaller first', async () => {
            const sortedTokens =
                token0.address < token1.address ? [token0.address, token1.address] : [token1.address, token0.address];
            const res = await carbonController.createPool(sortedTokens[1], sortedTokens[0]);
            await expect(res).to.emit(carbonController, 'PoolCreated').withArgs(1, sortedTokens[0], sortedTokens[1]);
        });
    });

    it('gets a pool matching the provided tokens', async () => {
        await carbonController.createPool(pool.token0, pool.token1);
        const tokens = sortTokens(pool.token0, pool.token1);

        const _pool = await carbonController.pool(pool.token0, pool.token1);
        expect(_pool.id.toNumber()).to.eq(1);
        expect(_pool.token0).to.eq(tokens[0]);
        expect(_pool.token1).to.eq(tokens[1]);
    });

    it('gets a pool matching the provided unsorted tokens', async () => {
        const tokens = sortTokens(pool.token0, pool.token1);
        await carbonController.createPool(tokens[0], tokens[1]);
        const _pool = await carbonController.pool(tokens[1], tokens[0]);
        expect(_pool.id.toNumber()).to.eq(1);
        expect(_pool.token0).to.eq(tokens[0]);
        expect(_pool.token1).to.eq(tokens[1]);
    });

    it('lists all supported tokens', async () => {
        await carbonController.createPool(pool.token0, pool.token1);
        const pairs = await carbonController.pairs();
        const tokens = sortTokens(pool.token0, pool.token1);
        expect(pairs).to.deep.eq([[tokens[0], tokens[1]]]);
    });

    describe('_poolById unit tests', () => {
        it('reverts when trying to fetch a pool by an id that does not exist', async () => {
            const testPools = await Contracts.TestPools.deploy();
            await testPools.test_createPool(token0.address, token1.address);
            await expect(testPools.test_poolById(2)).to.be.revertedWithError('PoolDoesNotExist');
        });
    });
});
