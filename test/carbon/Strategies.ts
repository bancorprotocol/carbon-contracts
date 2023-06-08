import Contracts, {
    TestCarbonController,
    TestERC20Burnable,
    TestERC20FeeOnTransfer,
    Voucher
} from '../../components/Contracts';
import { StrategyStruct } from '../../typechain-types/contracts/carbon/CarbonController';
import {
    DEFAULT_TRADING_FEE_PPM,
    PPM_RESOLUTION,
    STRATEGY_UPDATE_REASON_EDIT,
    ZERO_ADDRESS
} from '../../utils/Constants';
import { Roles } from '../../utils/Roles';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../utils/TokenData';
import { toPPM } from '../../utils/Types';
import {
    createBurnableToken,
    createCarbonController,
    createFeeOnTransferToken,
    createProxy,
    createSystem,
    Tokens
} from '../helpers/Factory';
import { shouldHaveGap } from '../helpers/Proxy';
import { getBalance, transfer } from '../helpers/Utils';
import {
    CreateStrategyParams,
    generateStrategyId,
    generateTestOrder,
    TestOrder,
    UpdateStrategyParams
} from './trading/tradingHelpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, ContractTransaction } from 'ethers';
import { ethers } from 'hardhat';

const SID1 = generateStrategyId(1, 1);
const SID2 = generateStrategyId(1, 2);
const SID3 = generateStrategyId(2, 3);

const permutations = [
    { token0: TokenSymbol.ETH, token1: TokenSymbol.TKN0 },
    { token0: TokenSymbol.TKN0, token1: TokenSymbol.ETH },
    { token0: TokenSymbol.TKN0, token1: TokenSymbol.TKN1 }
];

describe('Strategy', () => {
    let deployer: SignerWithAddress;
    let owner: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let carbonController: TestCarbonController;
    let token0: TestERC20Burnable;
    let token1: TestERC20Burnable;
    let token2: TestERC20Burnable;
    let feeOnTransferToken: TestERC20FeeOnTransfer;
    let voucher: Voucher;
    let tokens: Tokens = {};

    shouldHaveGap('Strategies', '_strategyCounter');

    before(async () => {
        [deployer, owner, nonAdmin] = await ethers.getSigners();
    });

    beforeEach(async () => {
        ({ carbonController, voucher } = await createSystem());

        tokens = {};
        for (const symbol of [TokenSymbol.ETH, TokenSymbol.TKN0, TokenSymbol.TKN1, TokenSymbol.TKN2]) {
            tokens[symbol] = await createBurnableToken(new TokenData(symbol));
        }

        token0 = tokens[TokenSymbol.TKN0];
        token1 = tokens[TokenSymbol.TKN1];
        token2 = tokens[TokenSymbol.TKN2];
        feeOnTransferToken = await createFeeOnTransferToken(new TokenData(TokenSymbol.TKN));
    });

    /**
     * creates a test strategy, handles funding and approvals
     * @returns a createStrategy transaction
     */
    const createStrategy = async (params?: CreateStrategyParams) => {
        // prepare variables
        const _params = { ...params };
        const order = _params.order ? _params.order : generateTestOrder();
        const _owner = _params.owner ? _params.owner : owner;
        const _tokens = [_params.token0 ? _params.token0 : token0, _params.token1 ? _params.token1 : token1];
        const amounts = [order.y, order.y];

        if (_params.token0Amount != null) {
            amounts[0] = BigNumber.from(_params.token0Amount);
        }

        if (_params.token1Amount != null) {
            amounts[1] = BigNumber.from(_params.token1Amount);
        }

        // keep track of gas usage
        let gasUsed = BigNumber.from(0);
        let txValue = BigNumber.from(0);

        // fund and approve
        for (let i = 0; i < 2; i++) {
            const token = _tokens[i];
            if (token.address === NATIVE_TOKEN_ADDRESS) {
                txValue = amounts[i];
            } else {
                // optionally skip funding
                if (!_params.skipFunding) {
                    await token.transfer(_owner.address, order.y);
                }
                const tx = await token.connect(_owner).approve(carbonController.address, amounts[i]);
                const receipt = await tx.wait();
                gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));
            }
        }

        if (_params.sendWithExcessNativeTokenValue) {
            txValue = BigNumber.from(txValue).add(10000);
        }

        // create strategy
        const tx = await carbonController.connect(_owner).createStrategy(
            _tokens[0].address,
            _tokens[1].address,
            [
                { ...order, y: amounts[0] },
                { ...order, y: amounts[1] }
            ],
            { value: txValue }
        );
        const receipt = await tx.wait();
        gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));

        return { tx, gasUsed };
    };

    /**
     * updates a test strategy, handles funding and approvals
     * @returns an updateStrategy transaction
     */
    const updateStrategy = async (params?: UpdateStrategyParams) => {
        const defaults = {
            owner,
            token0,
            token1,
            strategyId: SID1,
            skipFunding: false,
            order0Delta: 100,
            order1Delta: -100
        };
        const _params = { ...defaults, ...params };

        // keep track of gas usage
        let gasUsed = BigNumber.from(0);

        const tokens = [_params.token0, _params.token1];
        const deltas = [BigNumber.from(_params.order0Delta), BigNumber.from(_params.order1Delta)];

        let txValue = BigNumber.from(0);
        for (let i = 0; i < 2; i++) {
            const token = tokens[i];
            const delta = deltas[i];

            if (token.address === NATIVE_TOKEN_ADDRESS) {
                // only positive deltas (deposits) require funding
                if (delta.gt(0)) {
                    txValue = txValue.add(delta);
                }
            } else {
                // only positive deltas (deposits) requires funding
                if (delta.gt(0)) {
                    // optionally, skip the funding
                    if (!_params.skipFunding) {
                        await token.transfer(_params.owner.address, delta);
                    }

                    // approve the tx
                    const tx = await token.connect(_params.owner).approve(carbonController.address, delta);

                    // count the gas
                    const receipt = await tx.wait();
                    gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));
                }
            }
        }

        if (_params.sendWithExcessNativeTokenValue) {
            txValue = BigNumber.from(txValue).add(10000);
        }

        // prepare orders
        const currentOrder = generateTestOrder();
        const token0NewOrder = { ...currentOrder };
        const token1NewOrder = { ...currentOrder };
        let p: keyof typeof currentOrder;
        for (p in currentOrder) {
            token0NewOrder[p] = currentOrder[p].add(deltas[0]);
            token1NewOrder[p] = currentOrder[p].add(deltas[1]);
        }

        // update strategy
        const tx = await carbonController.connect(owner).updateStrategy(
            _params.strategyId,

            [currentOrder, currentOrder],
            [token0NewOrder, token1NewOrder],
            {
                value: txValue
            }
        );
        const receipt = await tx.wait();
        gasUsed = gasUsed.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));

        // return values
        return { tx, gasUsed };
    };

    /**
     * performs a fee withdrawal
     */
    const withdrawFees = async (
        feeAmount: BigNumber,
        withdrawAmount: BigNumber,
        token: TestERC20Burnable
    ): Promise<ContractTransaction> => {
        await carbonController.testSetAccumulatedFees(token.address, feeAmount);
        await carbonController.connect(deployer).grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, owner.address);
        return carbonController.connect(owner).withdrawFees(token.address, withdrawAmount, owner.address);
    };

    describe('strategy creation', async () => {
        it('reverts when addresses are identical', async () => {
            const order = generateTestOrder();
            await expect(
                carbonController.createStrategy(token0.address, token0.address, [order, order])
            ).to.be.revertedWithError('IdenticalAddresses');
        });

        describe('stores the information correctly', async () => {
            const _permutations = [
                { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.TKN0, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.TKN1, token1Amount: 100 },

                { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.TKN0, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.TKN1, token1Amount: 0 },

                { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.TKN0, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.TKN1, token1Amount: 100 },

                { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.TKN0, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.TKN1, token1Amount: 0 }
            ];
            for (const { token0, token1, token0Amount, token1Amount } of _permutations) {
                it(`(${token0}->${token1}) token0Amount: ${token0Amount} | token1Amount: ${token1Amount}`, async () => {
                    // prepare variables
                    const { z, A, B } = generateTestOrder();
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];

                    // create strategy
                    await createStrategy({ token0: _token0, token1: _token1, token0Amount, token1Amount });

                    // fetch the strategy created
                    const strategy = await carbonController.strategy(SID1);

                    // prepare a result object
                    const result = {
                        id: strategy.id.toString(),
                        owner: strategy.owner,
                        tokens: strategy.tokens,
                        orders: strategy.orders.map((o: any) => ({
                            y: o.y.toString(),
                            z: o.z.toString(),
                            A: o.A.toString(),
                            B: o.B.toString()
                        }))
                    };

                    // prepare the expected result object
                    const amounts = [token0Amount, token1Amount];
                    const _tokens = [tokens[token0], tokens[token1]];

                    const expectedResult: StrategyStruct = {
                        id: SID1.toString(),
                        owner: owner.address,
                        tokens: [_tokens[0].address, _tokens[1].address],
                        orders: [
                            { y: amounts[0].toString(), z: z.toString(), A: A.toString(), B: B.toString() },
                            { y: amounts[1].toString(), z: z.toString(), A: A.toString(), B: B.toString() }
                        ]
                    };

                    // assert
                    await expect(expectedResult).to.deep.equal(result);
                });
            }
        });

        describe('reverts for non valid addresses', async () => {
            const _permutations = [
                { token0: TokenSymbol.TKN0, token1: ZERO_ADDRESS },
                { token0: ZERO_ADDRESS, token1: TokenSymbol.TKN1 },
                { token0: ZERO_ADDRESS, token1: ZERO_ADDRESS }
            ];

            const order = generateTestOrder();
            for (const { token0, token1 } of _permutations) {
                it(`(${token0}->${token1})`, async () => {
                    const _token0 = tokens[token0] ? tokens[token0].address : ZERO_ADDRESS;
                    const _token1 = tokens[token1] ? tokens[token1].address : ZERO_ADDRESS;
                    await expect(
                        carbonController.createStrategy(_token0, _token1, [order, order])
                    ).to.be.revertedWithError('InvalidAddress');
                });
            }
        });

        it('emits the StrategyCreated event', async () => {
            const { y, z, A, B } = generateTestOrder();

            const { tx } = await createStrategy();
            await expect(tx)
                .to.emit(carbonController, 'StrategyCreated')
                .withArgs(
                    SID1,
                    owner.address,
                    token0.address,
                    token1.address,
                    [BigNumber.from(y), BigNumber.from(z), BigNumber.from(A), BigNumber.from(B)],
                    [BigNumber.from(y), BigNumber.from(z), BigNumber.from(A), BigNumber.from(B)]
                );
        });

        it('mints a voucher token to the caller', async () => {
            await createStrategy();
            const balance = await voucher.balanceOf(owner.address);
            const tokenOwner = await voucher.ownerOf(SID1);
            expect(balance).to.eq(1);
            expect(tokenOwner).to.eq(owner.address);
        });

        it('emits the voucher Transfer event', async () => {
            const { tx } = await createStrategy();
            await expect(tx).to.emit(voucher, 'Transfer').withArgs(ZERO_ADDRESS, owner.address, SID1);
        });

        it('increases strategyId', async () => {
            await createStrategy();
            await createStrategy();

            const strategy = await carbonController.strategy(SID2);
            expect(strategy.id).to.eq(SID2);
        });

        describe('balances are updated correctly', () => {
            const _permutations = [
                { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.TKN0, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.TKN1, token1Amount: 100 },

                { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.TKN0, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.TKN1, token1Amount: 0 },

                { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.TKN0, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.TKN1, token1Amount: 100 },

                { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.TKN0, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.TKN1, token1Amount: 0 }
            ];

            for (const { token0, token1, token0Amount, token1Amount } of _permutations) {
                it(`(${token0}->${token1}) token0Amount: ${token0Amount} | token1Amount: ${token1Amount}`, async () => {
                    // prepare variables
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];
                    const amounts = [BigNumber.from(token0Amount), BigNumber.from(token1Amount)];

                    const balanceTypes = [
                        { type: 'ownerToken0', token: _token0, account: owner.address },
                        { type: 'ownerToken1', token: _token1, account: owner.address },
                        { type: 'controllerToken0', token: _token0, account: carbonController.address },
                        { type: 'controllerToken1', token: _token1, account: carbonController.address }
                    ];

                    // fund the owner
                    await transfer(deployer, _token0, owner, amounts[0]);
                    await transfer(deployer, _token1, owner, amounts[1]);

                    // fetch balances before creating
                    const before: any = {};
                    for (const b of balanceTypes) {
                        before[b.type] = await getBalance(b.token, b.account);
                    }

                    // create strategy
                    const { gasUsed } = await createStrategy({
                        token0Amount,
                        token1Amount,
                        token0: _token0,
                        token1: _token1,
                        skipFunding: true
                    });

                    // fetch balances after creating
                    const after: any = {};
                    for (const b of balanceTypes) {
                        after[b.type] = await getBalance(b.token, b.account);
                    }

                    // account for gas costs if the token is the native token;
                    const expectedOwnerAmountToken0 =
                        _token0.address === NATIVE_TOKEN_ADDRESS ? amounts[0].add(gasUsed) : amounts[0];
                    const expectedOwnerAmountToken1 =
                        _token1.address === NATIVE_TOKEN_ADDRESS ? amounts[1].add(gasUsed) : amounts[1];

                    // owner's balance should decrease y amount
                    expect(after.ownerToken0).to.eq(before.ownerToken0.sub(expectedOwnerAmountToken0));
                    expect(after.ownerToken1).to.eq(before.ownerToken1.sub(expectedOwnerAmountToken1));

                    // controller's balance should increase y amount
                    expect(after.controllerToken0).to.eq(before.controllerToken0.add(amounts[0]));
                    expect(after.controllerToken1).to.eq(before.controllerToken1.add(amounts[1]));
                });
            }
        });

        describe('excess native token is refunded', () => {
            const _permutations = [
                { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.TKN0, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 100 },

                { token0: TokenSymbol.ETH, token0Amount: 100, token1: TokenSymbol.TKN0, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 100, token1: TokenSymbol.ETH, token1Amount: 0 },

                { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.TKN0, token1Amount: 100 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 100 },

                { token0: TokenSymbol.ETH, token0Amount: 0, token1: TokenSymbol.TKN0, token1Amount: 0 },
                { token0: TokenSymbol.TKN0, token0Amount: 0, token1: TokenSymbol.ETH, token1Amount: 0 }
            ];

            for (const { token0, token1, token0Amount, token1Amount } of _permutations) {
                it(`(${token0}->${token1}) token0Amount: ${token0Amount} | token1Amount: ${token1Amount}`, async () => {
                    // prepare variables
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];
                    const amounts = [BigNumber.from(token0Amount), BigNumber.from(token1Amount)];

                    const balanceTypes = [
                        { type: 'ownerToken0', token: _token0, account: owner.address },
                        { type: 'ownerToken1', token: _token1, account: owner.address },
                        { type: 'controllerToken0', token: _token0, account: carbonController.address },
                        { type: 'controllerToken1', token: _token1, account: carbonController.address }
                    ];

                    // fund the owner
                    await transfer(deployer, _token0, owner, amounts[0]);
                    await transfer(deployer, _token1, owner, amounts[1]);

                    // fetch balances before creating
                    const before: any = {};
                    for (const b of balanceTypes) {
                        before[b.type] = await getBalance(b.token, b.account);
                    }

                    // create strategy
                    const { gasUsed } = await createStrategy({
                        token0Amount,
                        token1Amount,
                        token0: _token0,
                        token1: _token1,
                        skipFunding: true,
                        sendWithExcessNativeTokenValue: true
                    });

                    // fetch balances after creating
                    const after: any = {};
                    for (const b of balanceTypes) {
                        after[b.type] = await getBalance(b.token, b.account);
                    }

                    // account for gas costs if the token is the native token;
                    const expectedOwnerAmountToken0 =
                        _token0.address === NATIVE_TOKEN_ADDRESS ? amounts[0].add(gasUsed) : amounts[0];
                    const expectedOwnerAmountToken1 =
                        _token1.address === NATIVE_TOKEN_ADDRESS ? amounts[1].add(gasUsed) : amounts[1];

                    // owner's balance should decrease y amount
                    expect(after.ownerToken0).to.eq(before.ownerToken0.sub(expectedOwnerAmountToken0));
                    expect(after.ownerToken1).to.eq(before.ownerToken1.sub(expectedOwnerAmountToken1));

                    // controller's balance should increase y amount
                    expect(after.controllerToken0).to.eq(before.controllerToken0.add(amounts[0]));
                    expect(after.controllerToken1).to.eq(before.controllerToken1.add(amounts[1]));
                });
            }
        });

        it('reverts when unnecessary native token was sent', async () => {
            const order = generateTestOrder();
            await expect(
                carbonController.createStrategy(token0.address, token1.address, [order, order], { value: 1000 })
            ).to.be.revertedWithError('UnnecessaryNativeTokenReceived');
        });

        it('reverts for fee on transfer tokens', async () => {
            const order = generateTestOrder();
            await feeOnTransferToken.approve(carbonController.address, order.y);
            await token0.approve(carbonController.address, order.y);
            await token1.approve(carbonController.address, order.y);
            await expect(
                carbonController.createStrategy(feeOnTransferToken.address, token1.address, [order, order])
            ).to.be.revertedWithError('BalanceMismatch');
            await expect(
                carbonController.createStrategy(token0.address, feeOnTransferToken.address, [order, order])
            ).to.be.revertedWithError('BalanceMismatch');
            // set fee side
            await feeOnTransferToken.approve(carbonController.address, order.y.mul(2));
            await feeOnTransferToken.setFeeSide(false);
            await expect(
                carbonController.createStrategy(feeOnTransferToken.address, token1.address, [order, order])
            ).to.be.revertedWithError('BalanceMismatch');
            await expect(
                carbonController.createStrategy(token0.address, feeOnTransferToken.address, [order, order])
            ).to.be.revertedWithError('BalanceMismatch');
        });

        it('reverts when paused', async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_EMERGENCY_STOPPER, nonAdmin.address);
            await carbonController.connect(nonAdmin).pause();
            const order = generateTestOrder();
            await expect(
                carbonController.createStrategy(token0.address, token1.address, [order, order])
            ).to.be.revertedWithError('Pausable: paused');
        });

        describe('reverts when the capacity is smaller than the liquidity', () => {
            const _permutations = [
                { order0Insufficient: true, order1Insufficient: false },
                { order0Insufficient: false, order1Insufficient: true },
                { order0Insufficient: true, order1Insufficient: true }
            ];

            for (const { order0Insufficient, order1Insufficient } of _permutations) {
                it(`order 0 invalid: ${order0Insufficient}, order 1 invalid: ${order1Insufficient}`, async () => {
                    const order = generateTestOrder();
                    const newInvalidOrder = { ...order, z: order.y.sub(1) };
                    const newValidOrder = { ...order, z: order.y.add(1) };
                    const order0 = order0Insufficient ? newInvalidOrder : newValidOrder;
                    const order1 = order1Insufficient ? newInvalidOrder : newValidOrder;

                    await expect(
                        carbonController.connect(owner).createStrategy(token0.address, token1.address, [order0, order1])
                    ).to.be.revertedWithError('InsufficientCapacity');
                });
            }
        });

        describe('reverts when any of the rates are invalid', () => {
            for (const orderId of [0, 1]) {
                for (const rateId of ['A', 'B']) {
                    it(`order ${orderId} rate ${rateId} invalid`, async () => {
                        const orders: any[2] = [generateTestOrder(), generateTestOrder()];
                        orders[orderId] = { ...orders[orderId], [rateId]: BigNumber.from(2).pow(64).sub(1) };

                        await expect(
                            carbonController.connect(owner).createStrategy(token0.address, token1.address, orders)
                        ).to.be.revertedWithError('InvalidRate');
                    });
                }
            }
        });

        describe('tokens sorting persist', () => {
            const _permutations = [
                { token0: TokenSymbol.TKN0, token1: TokenSymbol.TKN1 },
                { token0: TokenSymbol.TKN1, token1: TokenSymbol.TKN0 }
            ];

            for (const { token0, token1 } of _permutations) {
                it(`${token0}, ${token1}`, async () => {
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];
                    await createStrategy({ token0: _token0, token1: _token1 });
                    const strategy = await carbonController.strategy(SID1);
                    expect(strategy.tokens[0]).to.eq(_token0.address);
                    expect(strategy.tokens[1]).to.eq(_token1.address);
                });
            }
        });
    });

    describe('strategy updating', async () => {
        const _permutations = [
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.TKN1,
                order0Delta: 100,
                order1Delta: -100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.ETH,
                order0Delta: 100,
                order1Delta: -100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.ETH,
                token1: TokenSymbol.TKN0,
                order0Delta: 100,
                order1Delta: -100,
                sendWithExcessNativeTokenValue: false
            },

            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.TKN1,
                order0Delta: -100,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.ETH,
                order0Delta: -100,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.ETH,
                token1: TokenSymbol.TKN0,
                order0Delta: -100,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },

            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.TKN1,
                order0Delta: -100,
                order1Delta: -100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.ETH,
                order0Delta: -100,
                order1Delta: -100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.ETH,
                token1: TokenSymbol.TKN0,
                order0Delta: -100,
                order1Delta: -100,
                sendWithExcessNativeTokenValue: false
            },

            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.TKN1,
                order0Delta: 100,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.ETH,
                order0Delta: 100,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.ETH,
                token1: TokenSymbol.TKN0,
                order0Delta: 100,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },

            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.TKN1,
                order0Delta: 100,
                order1Delta: 0,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.ETH,
                order0Delta: 100,
                order1Delta: 0,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.ETH,
                token1: TokenSymbol.TKN0,
                order0Delta: 100,
                order1Delta: 0,
                sendWithExcessNativeTokenValue: false
            },

            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.TKN1,
                order0Delta: 0,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.TKN0,
                token1: TokenSymbol.ETH,
                order0Delta: 0,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            },
            {
                token0: TokenSymbol.ETH,
                token1: TokenSymbol.TKN0,
                order0Delta: 0,
                order1Delta: 100,
                sendWithExcessNativeTokenValue: false
            }
        ];

        describe('orders are stored correctly', async () => {
            for (const { token0, token1, order0Delta, order1Delta } of _permutations) {
                it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta}`, async () => {
                    // prepare variables
                    const { y, z, A, B } = generateTestOrder();
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];
                    const _tokens = [_token0, _token1];

                    // create strategy
                    await createStrategy({ token0: _tokens[0], token1: _tokens[1] });

                    // update strategy
                    await updateStrategy({
                        token0: _tokens[0],
                        token1: _tokens[1],
                        order0Delta,
                        order1Delta
                    });

                    // fetch the strategy created
                    const strategy = await carbonController.strategy(SID1);

                    // prepare a result object
                    const result = {
                        id: strategy.id.toString(),
                        owner: strategy.owner,
                        tokens: strategy.tokens,
                        orders: strategy.orders.map((o: any) => ({
                            y: o.y.toString(),
                            z: o.z.toString(),
                            A: o.A.toString(),
                            B: o.B.toString()
                        }))
                    };

                    // prepare the expected result object
                    const deltas = [order0Delta, order1Delta];
                    const expectedResult: StrategyStruct = {
                        id: SID1.toString(),
                        owner: owner.address,
                        tokens: [_tokens[0].address, _tokens[1].address],
                        orders: [
                            {
                                y: y.add(deltas[0]).toString(),
                                z: z.add(deltas[0]).toString(),
                                A: A.add(deltas[0]).toString(),
                                B: B.add(deltas[0]).toString()
                            },
                            {
                                y: y.add(deltas[1]).toString(),
                                z: z.add(deltas[1]).toString(),
                                A: A.add(deltas[1]).toString(),
                                B: B.add(deltas[1]).toString()
                            }
                        ]
                    };

                    // assert
                    await expect(expectedResult).to.deep.equal(result);
                });
            }
        });

        describe('orders are stored correctly without liquidity change', async () => {
            const _permutations = [
                { token0: TokenSymbol.TKN0, token1: TokenSymbol.TKN1, order0Delta: 1, order1Delta: -1 },
                { token0: TokenSymbol.ETH, token1: TokenSymbol.TKN0, order0Delta: 1, order1Delta: -1 },
                { token0: TokenSymbol.TKN0, token1: TokenSymbol.ETH, order0Delta: 1, order1Delta: -1 },

                { token0: TokenSymbol.TKN0, token1: TokenSymbol.TKN1, order0Delta: -1, order1Delta: 1 },
                { token0: TokenSymbol.ETH, token1: TokenSymbol.TKN0, order0Delta: -1, order1Delta: 1 },
                { token0: TokenSymbol.TKN0, token1: TokenSymbol.ETH, order0Delta: -1, order1Delta: 1 },

                { token0: TokenSymbol.TKN0, token1: TokenSymbol.TKN1, order0Delta: -1, order1Delta: -1 },
                { token0: TokenSymbol.ETH, token1: TokenSymbol.TKN0, order0Delta: -1, order1Delta: -1 },
                { token0: TokenSymbol.TKN0, token1: TokenSymbol.ETH, order0Delta: -1, order1Delta: -1 },

                { token0: TokenSymbol.TKN0, token1: TokenSymbol.TKN1, order0Delta: 1, order1Delta: 1 },
                { token0: TokenSymbol.ETH, token1: TokenSymbol.TKN0, order0Delta: 1, order1Delta: 1 },
                { token0: TokenSymbol.TKN0, token1: TokenSymbol.ETH, order0Delta: 1, order1Delta: 1 }
            ];
            for (const { token0, token1, order0Delta, order1Delta } of _permutations) {
                it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta}`, async () => {
                    // prepare variables
                    const order = generateTestOrder();
                    const newOrders: TestOrder[] = [];
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];
                    const deltas = [order0Delta, order1Delta];

                    // prepare new orders
                    for (let i = 0; i < 2; i++) {
                        newOrders.push({
                            y: order.y,
                            z: order.z.add(deltas[i]),
                            A: order.A.add(deltas[i]),
                            B: order.B.add(deltas[i])
                        });
                    }

                    // create strategy
                    await createStrategy({ token0: _token0, token1: _token1 });

                    // update strategy
                    await carbonController
                        .connect(owner)
                        .updateStrategy(SID1, [order, order], [newOrders[0], newOrders[1]]);

                    // fetch the strategy created
                    const strategy = await carbonController.strategy(SID1);

                    // prepare a result object
                    const result = {
                        id: strategy.id.toString(),
                        owner: strategy.owner,
                        tokens: strategy.tokens,
                        orders: strategy.orders.map((o: any) => ({
                            y: o.y,
                            z: o.z,
                            A: o.A,
                            B: o.B
                        }))
                    };

                    // prepare the expected result object
                    const expectedResult: StrategyStruct = {
                        id: SID1.toString(),
                        owner: owner.address,
                        tokens: [_token0.address, _token1.address],
                        orders: [newOrders[0], newOrders[1]]
                    };

                    // assert
                    await expect(expectedResult).to.deep.equal(result);
                });
            }
        });

        describe('balances are updated correctly', () => {
            const strategyUpdatingPermutations = [
                ..._permutations,
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: 100,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: 100,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                }
            ];
            for (const {
                token0,
                token1,
                order0Delta,
                order1Delta,
                sendWithExcessNativeTokenValue
            } of strategyUpdatingPermutations) {
                // eslint-disable-next-line max-len
                it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta} | excess: ${sendWithExcessNativeTokenValue}`, async () => {
                    // prepare variables
                    const _tokens = [tokens[token0], tokens[token1]];
                    const deltas = [BigNumber.from(order0Delta), BigNumber.from(order1Delta)];

                    const delta0 = deltas[0];
                    const delta1 = deltas[1];
                    const balanceTypes = [
                        { type: 'ownerToken0', token: _tokens[0], account: owner.address },
                        { type: 'ownerToken1', token: _tokens[1], account: owner.address },
                        { type: 'controllerToken0', token: _tokens[0], account: carbonController.address },
                        { type: 'controllerToken1', token: _tokens[1], account: carbonController.address }
                    ];

                    // create strategy
                    await createStrategy({ token0: _tokens[0], token1: _tokens[1] });

                    // fund user
                    for (let i = 0; i < 2; i++) {
                        const delta = deltas[i];
                        if (delta.gt(0)) {
                            await transfer(deployer, _tokens[i], owner, deltas[i]);
                        }
                    }

                    // fetch balances before updating
                    const before: any = {};
                    for (const b of balanceTypes) {
                        before[b.type] = await getBalance(b.token, b.account);
                    }

                    // perform update
                    const { gasUsed } = await updateStrategy({
                        order0Delta,
                        order1Delta,
                        token0: _tokens[0],
                        token1: _tokens[1],
                        skipFunding: true,
                        sendWithExcessNativeTokenValue
                    });

                    // fetch balances after creating
                    const after: any = {};
                    for (const b of balanceTypes) {
                        after[b.type] = await getBalance(b.token, b.account);
                    }

                    // account for gas costs if the token is the native token;
                    const expectedOwnerDeltaToken0 =
                        _tokens[0].address === NATIVE_TOKEN_ADDRESS ? delta0.add(gasUsed) : delta0;
                    const expectedOwnerDeltaToken1 =
                        _tokens[1].address === NATIVE_TOKEN_ADDRESS ? delta1.add(gasUsed) : delta1;

                    // assert
                    expect(after.ownerToken0).to.eq(before.ownerToken0.sub(expectedOwnerDeltaToken0));
                    expect(after.ownerToken1).to.eq(before.ownerToken1.sub(expectedOwnerDeltaToken1));
                    expect(after.controllerToken0).to.eq(before.controllerToken0.add(delta0));
                    expect(after.controllerToken1).to.eq(before.controllerToken1.add(delta1));
                });
            }
        });

        describe('excess native token is refunded when updating without full withdrawal', () => {
            const strategyUpdatingPermutations = [
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: 100,
                    order1Delta: -100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: 100,
                    order1Delta: -100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: -100,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: -100,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: -100,
                    order1Delta: -100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: -100,
                    order1Delta: -100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: 100,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: 100,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: 100,
                    order1Delta: 0,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: 100,
                    order1Delta: 0,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: 0,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: 0,
                    order1Delta: 100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: -100,
                    order1Delta: 0,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: -100,
                    order1Delta: 0,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.TKN0,
                    token1: TokenSymbol.ETH,
                    order0Delta: 0,
                    order1Delta: -100,
                    sendWithExcessNativeTokenValue: true
                },
                {
                    token0: TokenSymbol.ETH,
                    token1: TokenSymbol.TKN0,
                    order0Delta: 0,
                    order1Delta: -100,
                    sendWithExcessNativeTokenValue: true
                }
            ];
            for (const {
                token0,
                token1,
                order0Delta,
                order1Delta,
                sendWithExcessNativeTokenValue
            } of strategyUpdatingPermutations) {
                // eslint-disable-next-line max-len
                it(`(${token0},${token1}) | order0Delta: ${order0Delta} | order1Delta: ${order1Delta} | excess: ${sendWithExcessNativeTokenValue}`, async () => {
                    // prepare variables
                    const _tokens = [tokens[token0], tokens[token1]];
                    const deltas = [BigNumber.from(order0Delta), BigNumber.from(order1Delta)];

                    const delta0 = deltas[0];
                    const delta1 = deltas[1];
                    const balanceTypes = [
                        { type: 'ownerToken0', token: _tokens[0], account: owner.address },
                        { type: 'ownerToken1', token: _tokens[1], account: owner.address },
                        { type: 'controllerToken0', token: _tokens[0], account: carbonController.address },
                        { type: 'controllerToken1', token: _tokens[1], account: carbonController.address }
                    ];

                    // create strategy
                    await createStrategy({ token0: _tokens[0], token1: _tokens[1] });

                    // fund user
                    for (let i = 0; i < 2; i++) {
                        const delta = deltas[i];
                        if (delta.gt(0)) {
                            await transfer(deployer, _tokens[i], owner, deltas[i]);
                        }
                    }

                    // fetch balances before updating
                    const before: any = {};
                    for (const b of balanceTypes) {
                        before[b.type] = await getBalance(b.token, b.account);
                    }

                    // perform update
                    const { gasUsed } = await updateStrategy({
                        order0Delta,
                        order1Delta,
                        token0: _tokens[0],
                        token1: _tokens[1],
                        skipFunding: true,
                        sendWithExcessNativeTokenValue
                    });

                    // fetch balances after creating
                    const after: any = {};
                    for (const b of balanceTypes) {
                        after[b.type] = await getBalance(b.token, b.account);
                    }

                    // account for gas costs if the token is the native token;
                    const expectedOwnerDeltaToken0 =
                        _tokens[0].address === NATIVE_TOKEN_ADDRESS ? delta0.add(gasUsed) : delta0;
                    const expectedOwnerDeltaToken1 =
                        _tokens[1].address === NATIVE_TOKEN_ADDRESS ? delta1.add(gasUsed) : delta1;

                    // assert
                    expect(after.ownerToken0).to.eq(before.ownerToken0.sub(expectedOwnerDeltaToken0));
                    expect(after.ownerToken1).to.eq(before.ownerToken1.sub(expectedOwnerDeltaToken1));
                    expect(after.controllerToken0).to.eq(before.controllerToken0.add(delta0));
                    expect(after.controllerToken1).to.eq(before.controllerToken1.add(delta1));
                });
            }
        });

        describe('reverts if the provided reference tokens are not equal to the current', () => {
            const mutations = [{ y: 1 }, { z: 1 }, { A: 1 }, { B: 1 }];
            for (const mutation of mutations) {
                for (const [key, value] of Object.entries(mutation)) {
                    it(`reverts for a mutation in ${key}`, async () => {
                        await createStrategy();
                        const order: any = generateTestOrder();
                        order[key] = BigNumber.from(value).add(order[key]);
                        const tx = carbonController.connect(owner).updateStrategy(SID1, [order, order], [order, order]);
                        await expect(tx).to.have.been.revertedWithError('OutDated');
                    });
                }
            }
        });

        it('emits the StrategyUpdated event on edit', async () => {
            const { y, z, A, B } = generateTestOrder();
            const delta = 10;

            await createStrategy();

            const { tx } = await updateStrategy({ order0Delta: delta, order1Delta: delta });

            const expectedOrder = [y.add(delta), z.add(delta), A.add(delta), B.add(delta)];
            await expect(tx)
                .to.emit(carbonController, 'StrategyUpdated')
                .withArgs(
                    SID1,
                    token0.address,
                    token1.address,
                    expectedOrder,
                    expectedOrder,
                    STRATEGY_UPDATE_REASON_EDIT
                );
        });

        it('reverts when unnecessary native token was sent', async () => {
            const order = generateTestOrder();
            await createStrategy();

            const tx = carbonController.connect(owner).updateStrategy(SID1, [order, order], [order, order], {
                value: 100
            });
            await expect(tx).to.be.revertedWithError('UnnecessaryNativeTokenReceived');
        });

        it('reverts for fee on transfer tokens', async () => {
            const order = generateTestOrder();
            // disable fee to create strategy
            await feeOnTransferToken.setFeeEnabled(false);
            // approve
            await feeOnTransferToken.approve(carbonController.address, order.y);
            await token0.approve(carbonController.address, order.y);
            await token1.approve(carbonController.address, order.y);
            // create strategy
            await carbonController.createStrategy(feeOnTransferToken.address, token1.address, [order, order]);
            // enable fee to test strategy update
            await feeOnTransferToken.setFeeEnabled(true);
            // increase order y to trigger check
            const newOrder = generateTestOrder();
            newOrder.y = newOrder.y.add(1000);
            // approve
            await feeOnTransferToken.approve(carbonController.address, newOrder.y);
            await token0.approve(carbonController.address, order.y);
            await token1.approve(carbonController.address, order.y);
            let tx = carbonController.updateStrategy(SID1, [order, order], [newOrder, newOrder]);
            await expect(tx).to.be.revertedWithError('BalanceMismatch');
            // change fee side
            await feeOnTransferToken.setFeeSide(false);
            tx = carbonController.updateStrategy(SID1, [order, order], [newOrder, newOrder]);
            await expect(tx).to.be.revertedWithError('BalanceMismatch');
        });

        it('reverts when paused', async () => {
            await createStrategy();
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_EMERGENCY_STOPPER, nonAdmin.address);
            await carbonController.connect(nonAdmin).pause();

            const order = generateTestOrder();
            const tx = carbonController.updateStrategy(1, [order, order], [order, order]);
            await expect(tx).to.be.revertedWithError('Pausable: paused');
        });

        it('reverts when trying to update a non existing strategy on an existing pair', async () => {
            await createStrategy();
            const order = generateTestOrder();
            await expect(
                carbonController.connect(owner).updateStrategy(SID2, [order, order], [order, order])
            ).to.be.revertedWithError('ERC721: invalid token ID');
        });

        it('reverts when trying to update a non existing strategy on a non existing pair', async () => {
            await createStrategy();
            const order = generateTestOrder();
            await expect(
                carbonController.connect(owner).updateStrategy(SID3, [order, order], [order, order])
            ).to.be.revertedWithError('PairDoesNotExist');
        });

        it('reverts when the provided strategy id is zero', async () => {
            const order = generateTestOrder();
            await expect(
                carbonController.connect(owner).updateStrategy(0, [order, order], [order, order])
            ).to.be.revertedWithError('PairDoesNotExist');
        });

        it('reverts when a non owner attempts to delete a strategy', async () => {
            await createStrategy();
            const order = generateTestOrder();
            await expect(
                carbonController.connect(nonAdmin).updateStrategy(SID1, [order, order], [order, order])
            ).to.be.revertedWithError('AccessDenied');
        });

        describe('reverts when the capacity is smaller than the liquidity', () => {
            const _permutations = [
                { order0Insufficient: true, order1Insufficient: false },
                { order0Insufficient: false, order1Insufficient: true },
                { order0Insufficient: true, order1Insufficient: true }
            ];

            for (const { order0Insufficient, order1Insufficient } of _permutations) {
                it(`order 0 invalid: ${order0Insufficient}, order 1 invalid: ${order1Insufficient}`, async () => {
                    const order = generateTestOrder();
                    const newInvalidOrder = { ...order, z: order.y.sub(1) };
                    const newValidOrder = { ...order, z: order.y.add(1) };
                    const order0 = order0Insufficient ? newInvalidOrder : newValidOrder;
                    const order1 = order1Insufficient ? newInvalidOrder : newValidOrder;

                    await createStrategy();
                    await expect(
                        carbonController.connect(owner).updateStrategy(SID1, [order, order], [order0, order1])
                    ).to.be.revertedWithError('InsufficientCapacity');
                });
            }
        });

        describe('reverts when any of the rates are invalid', () => {
            for (const orderId of [0, 1]) {
                for (const rateId of ['A', 'B']) {
                    it(`order ${orderId} rate ${rateId} invalid`, async () => {
                        const oldOrders: any[2] = [generateTestOrder(), generateTestOrder()];
                        const newOrders: any[2] = [generateTestOrder(), generateTestOrder()];
                        newOrders[orderId] = { ...newOrders[orderId], [rateId]: BigNumber.from(2).pow(64).sub(1) };

                        await createStrategy();
                        await expect(
                            carbonController.connect(owner).updateStrategy(SID1, oldOrders, newOrders)
                        ).to.be.revertedWithError('InvalidRate');
                    });
                }
            }
        });
    });

    describe('strategy deletion', () => {
        describe('voucher burns following a deletion', () => {
            for (const { token0, token1 } of permutations) {
                it(`(${token0}->${token1})`, async () => {
                    await createStrategy({ token0: tokens[token0], token1: tokens[token1] });
                    await carbonController.connect(owner).deleteStrategy(SID1);
                    await expect(voucher.ownerOf(SID1)).to.be.revertedWithError('ERC721: invalid token ID');
                });
            }
        });

        describe('balances are updated correctly', () => {
            for (const { token0, token1 } of permutations) {
                it(`(${token0}->${token1})`, async () => {
                    // prepare variables
                    const { y } = generateTestOrder();
                    const _token0 = tokens[token0];
                    const _token1 = tokens[token1];
                    const balanceTypes = [
                        { type: 'ownerToken0', token: _token0, account: owner.address },
                        { type: 'ownerToken1', token: _token1, account: owner.address },
                        { type: 'controllerToken0', token: _token0, account: carbonController.address },
                        { type: 'controllerToken1', token: _token1, account: carbonController.address }
                    ];

                    // fund the owner
                    await transfer(deployer, _token0, owner, y);
                    await transfer(deployer, _token1, owner, y);

                    // create strategy
                    await createStrategy({ token0: _token0, token1: _token1, skipFunding: true });

                    // fetch balances before deleting
                    const before: any = {};
                    for (const b of balanceTypes) {
                        before[b.type] = await getBalance(b.token, b.account);
                    }

                    // delete strategy
                    const tx = await carbonController.connect(owner).deleteStrategy(SID1);
                    const receipt = await tx.wait();
                    const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

                    // fetch balances after deleting
                    const after: any = {};
                    for (const b of balanceTypes) {
                        after[b.type] = await getBalance(b.token, b.account);
                    }

                    // account for gas costs if the token is the native token;
                    const expectedOwnerAmountToken0 = _token0.address === NATIVE_TOKEN_ADDRESS ? y.sub(gasUsed) : y;
                    const expectedOwnerAmountToken1 = _token1.address === NATIVE_TOKEN_ADDRESS ? y.sub(gasUsed) : y;

                    // owner's balance should increase y amount
                    expect(after.ownerToken0).to.eq(before.ownerToken0.add(expectedOwnerAmountToken0));
                    expect(after.ownerToken1).to.eq(before.ownerToken1.add(expectedOwnerAmountToken1));

                    // controller's balance should decrease y amount
                    expect(after.controllerToken0).to.eq(before.controllerToken0.sub(y));
                    expect(after.controllerToken1).to.eq(before.controllerToken1.sub(y));
                });
            }
        });

        describe('clearing storage', () => {
            for (const { token0, token1 } of permutations) {
                it(`(${token0}->${token1})`, async () => {
                    // create a strategy
                    await createStrategy({ token0: tokens[token0], token1: tokens[token1] });

                    // assert before deleting
                    const strategy = await carbonController.strategy(SID1);
                    let strategiesByPair = await carbonController.strategiesByPair(
                        tokens[token0].address,
                        tokens[token1].address,
                        0,
                        0
                    );
                    expect(strategy.id).to.eq(SID1);
                    expect(strategiesByPair[0].id).to.eq(SID1);

                    // delete strategy
                    await carbonController.connect(owner).deleteStrategy(strategy.id);

                    // assert after deleting
                    await expect(carbonController.connect(owner).strategy(strategy.id)).to.be.revertedWithError(
                        'ERC721: invalid token ID'
                    );
                    strategiesByPair = await carbonController.strategiesByPair(
                        tokens[token0].address,
                        tokens[token1].address,
                        0,
                        0
                    );
                    expect(strategiesByPair.length).to.eq(0);
                });
            }
        });

        it('emits the StrategyDeleted event', async () => {
            // create strategy
            await createStrategy();

            // prepare variables and transaction
            const { y, z, A, B } = generateTestOrder();
            const tx = carbonController.connect(owner).deleteStrategy(SID1);

            // assert
            await expect(tx)
                .to.emit(carbonController, 'StrategyDeleted')
                .withArgs(
                    SID1,
                    owner.address,
                    token0.address,
                    token1.address,
                    [BigNumber.from(y), BigNumber.from(z), BigNumber.from(A), BigNumber.from(B)],
                    [BigNumber.from(y), BigNumber.from(z), BigNumber.from(A), BigNumber.from(B)]
                );
        });

        it('should be able to delete a disabled order', async () => {
            // edit the test order and disable it by setting all rates to 0
            const order = generateTestOrder();
            order.A = BigNumber.from(0);
            order.B = BigNumber.from(0);
            order.y = BigNumber.from(0);
            order.z = BigNumber.from(0);
            // create strategy
            await createStrategy({ order });

            // prepare variables and transaction
            const tx = carbonController.connect(owner).deleteStrategy(SID1);

            // assert
            await expect(tx).to.emit(carbonController, 'StrategyDeleted');
        });

        it('reverts when provided strategy id is zero', async () => {
            await createStrategy();

            await expect(carbonController.deleteStrategy(0)).to.be.revertedWithError('PairDoesNotExist');
        });

        it('reverts when a non owner attempts to delete a strategy', async () => {
            await createStrategy();

            await expect(carbonController.connect(nonAdmin).deleteStrategy(SID1)).to.be.revertedWithError(
                'AccessDenied'
            );
        });

        it('reverts when trying to delete a non existing strategy on an existing pair', async () => {
            await createStrategy();

            await expect(carbonController.connect(owner).deleteStrategy(SID2)).to.be.revertedWithError(
                'ERC721: invalid token ID'
            );
        });

        it('reverts when trying to delete a non existing strategy on a non existing pair', async () => {
            await createStrategy();

            await expect(carbonController.connect(owner).deleteStrategy(SID3)).to.be.revertedWithError(
                'PairDoesNotExist'
            );
        });

        it('reverts when paused', async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_EMERGENCY_STOPPER, nonAdmin.address);
            await createStrategy();
            await carbonController.connect(nonAdmin).pause();
            await expect(carbonController.connect(owner).deleteStrategy(SID1)).to.be.revertedWithError(
                'Pausable: paused'
            );
        });
    });

    describe('trading fee', () => {
        const newTradingFee = toPPM(30);

        it('should revert when a non-admin attempts to set the trading fee', async () => {
            await expect(carbonController.connect(owner).setTradingFeePPM(newTradingFee)).to.be.revertedWithError(
                'AccessDenied'
            );
        });

        it('should revert when setting the trading fee to an invalid value', async () => {
            await expect(carbonController.setTradingFeePPM(PPM_RESOLUTION + 1)).to.be.revertedWithError('InvalidFee');
        });

        it('should ignore updating to the same trading fee', async () => {
            await carbonController.setTradingFeePPM(newTradingFee);

            const res = await carbonController.setTradingFeePPM(newTradingFee);
            await expect(res).not.to.emit(carbonController, 'TradingFeePPMUpdated');
        });

        it('should be able to set and update the trading fee', async () => {
            const res = await carbonController.setTradingFeePPM(newTradingFee);
            await expect(res)
                .to.emit(carbonController, 'TradingFeePPMUpdated')
                .withArgs(DEFAULT_TRADING_FEE_PPM, newTradingFee);

            expect(await carbonController.tradingFeePPM()).to.equal(newTradingFee);
        });

        it('sets the default when initializing', async () => {
            expect(await carbonController.tradingFeePPM()).to.equal(DEFAULT_TRADING_FEE_PPM);
        });
    });

    describe('fetch by pair', () => {
        const FETCH_AMOUNT = 5;

        it('reverts when addresses are identical', async () => {
            const tx = carbonController.strategiesByPair(token0.address, token0.address, 0, 0);
            await expect(tx).to.be.revertedWithError('IdenticalAddresses');
        });

        it('reverts when no pair found for given tokens', async () => {
            const tx = carbonController.strategiesByPair(token0.address, token1.address, 0, 0);
            await expect(tx).to.be.revertedWithError('PairDoesNotExist');
        });

        describe('reverts for non valid addresses', async () => {
            const _permutations = [
                { token0: TokenSymbol.TKN0, token1: ZERO_ADDRESS },
                { token0: ZERO_ADDRESS, token1: TokenSymbol.TKN1 },
                { token0: ZERO_ADDRESS, token1: ZERO_ADDRESS }
            ];

            for (const { token0, token1 } of _permutations) {
                it(`(${token0}->${token1})`, async () => {
                    const _token0 = tokens[token0] ? tokens[token0].address : ZERO_ADDRESS;
                    const _token1 = tokens[token1] ? tokens[token1].address : ZERO_ADDRESS;
                    const tx = carbonController.strategiesByPair(_token0, _token1, 0, 0);
                    await expect(tx).to.be.revertedWithError('InvalidAddress');
                });
            }
        });

        it('fetches the correct strategies', async () => {
            await createStrategy();
            await createStrategy();
            await createStrategy({ token0, token1: token2 });

            let strategies = await carbonController.strategiesByPair(token0.address, token1.address, 0, 0);
            expect(strategies.length).to.eq(2);
            expect(strategies[0].id).to.eq(SID1);
            expect(strategies[1].id).to.eq(SID2);
            expect(strategies[0].tokens[0]).to.eq(token0.address);
            expect(strategies[0].tokens[1]).to.eq(token1.address);
            expect(strategies[1].tokens[0]).to.eq(token0.address);
            expect(strategies[1].tokens[1]).to.eq(token1.address);

            strategies = await carbonController.strategiesByPair(token0.address, token2.address, 0, 0);
            expect(strategies.length).to.eq(1);
            expect(strategies[0].id).to.eq(SID3);
            expect(strategies[0].tokens[0]).to.eq(token0.address);
            expect(strategies[0].tokens[1]).to.eq(token2.address);
        });

        it('sets endIndex to the maximum possible if provided with 0', async () => {
            for (let i = 0; i < FETCH_AMOUNT; i++) {
                await createStrategy({ token0, token1 });
            }
            const strategies = await carbonController.strategiesByPair(token0.address, token1.address, 0, 0);
            expect(strategies.length).to.eq(FETCH_AMOUNT);
        });

        it('sets endIndex to the maximum possible if provided with an out of bound value', async () => {
            for (let i = 0; i < FETCH_AMOUNT; i++) {
                await createStrategy({ token0, token1 });
            }
            const strategies = await carbonController.strategiesByPair(
                token0.address,
                token1.address,
                0,
                FETCH_AMOUNT + 100
            );
            expect(strategies.length).to.eq(FETCH_AMOUNT);
        });

        it('reverts if startIndex is greater than endIndex', async () => {
            for (let i = 0; i < FETCH_AMOUNT; i++) {
                await createStrategy({ token0, token1 });
            }
            const tx = carbonController.strategiesByPair(token0.address, token1.address, 6, 5);
            await expect(tx).to.have.been.revertedWithError('InvalidIndices');
        });
    });

    describe('fetch by pair count', () => {
        it('reverts when addresses are identical', async () => {
            const tx = carbonController.strategiesByPairCount(token0.address, token0.address);
            await expect(tx).to.be.revertedWithError('IdenticalAddresses');
        });

        it('reverts when no pair found for given tokens', async () => {
            const tx = carbonController.strategiesByPairCount(token0.address, token1.address);
            await expect(tx).to.be.revertedWithError('PairDoesNotExist');
        });

        it('returns the correct count', async () => {
            await createStrategy({ token0, token1 });
            await createStrategy({ token0, token1 });
            await createStrategy({ token0, token1 });
            await createStrategy({ token0: tokens[TokenSymbol.TKN2], token1: tokens[TokenSymbol.ETH] });
            await createStrategy({ token0: tokens[TokenSymbol.TKN2], token1: tokens[TokenSymbol.ETH] });
            await createStrategy({ token0: tokens[TokenSymbol.TKN2], token1: tokens[TokenSymbol.ETH] });

            const result1 = await carbonController.strategiesByPairCount(token0.address, token1.address);
            const result2 = await carbonController.strategiesByPairCount(
                tokens[TokenSymbol.TKN2].address,
                tokens[TokenSymbol.ETH].address
            );
            expect(result1).to.eq(3);
            expect(result2).to.eq(3);
        });

        describe('reverts for non valid addresses', async () => {
            const _permutations = [
                { token0: TokenSymbol.TKN0, token1: ZERO_ADDRESS },
                { token0: ZERO_ADDRESS, token1: TokenSymbol.TKN1 },
                { token0: ZERO_ADDRESS, token1: ZERO_ADDRESS }
            ];

            for (const { token0, token1 } of _permutations) {
                it(`(${token0}->${token1})`, async () => {
                    const _token0 = tokens[token0] ? tokens[token0].address : ZERO_ADDRESS;
                    const _token1 = tokens[token1] ? tokens[token1].address : ZERO_ADDRESS;
                    const tx = carbonController.strategiesByPairCount(_token0, _token1);
                    await expect(tx).to.be.revertedWithError('InvalidAddress');
                });
            }
        });
    });

    describe('fetch by a single id', async () => {
        it('reverts when fetching a non existing strategy on an existing pair', async () => {
            await createStrategy();
            await expect(carbonController.strategy(SID2)).to.be.revertedWithError('ERC721: invalid token ID');
        });

        it('reverts when fetching a non existing strategy on a non existing pair', async () => {
            await expect(carbonController.strategy(SID2)).to.be.revertedWithError('PairDoesNotExist');
        });

        it('reverts when the provided strategy id is zero', async () => {
            await expect(carbonController.strategy(0)).to.be.revertedWithError('PairDoesNotExist');
        });

        it('returns the correct strategy', async () => {
            await createStrategy();
            await createStrategy();
            const strategy = await carbonController.strategy(SID2);
            expect(strategy.id).to.eq(SID2);
        });
    });

    describe('voucher', () => {
        describe('transfers', () => {
            it("updates the voucher's owner following a transfer ", async () => {
                // create strategy
                await createStrategy();

                // transfer the voucher
                await voucher.connect(owner).transferFrom(owner.address, nonAdmin.address, SID1);

                // fetch tokens by owner
                const oldTokenIds = await voucher.tokensByOwner(owner.address, 0, 100);
                const newTokenIds = await voucher.tokensByOwner(nonAdmin.address, 0, 100);
                const newOwner = await voucher.ownerOf(SID1);

                // assert
                expect(oldTokenIds.length === 0);
                expect(newTokenIds[0].eq(SID1)).to.eq(true);
                expect(newOwner).to.eq(nonAdmin.address);
            });

            it('updates the strategy owner following a transfer', async () => {
                // create a strategy
                await createStrategy();

                // transfer the voucher
                await voucher.connect(owner).transferFrom(owner.address, nonAdmin.address, SID1);

                // fetch the strategy
                const strategy = await carbonController.strategy(SID1);

                // the strategy should have a new owner
                expect(strategy.owner).to.eq(nonAdmin.address);
            });

            it('reverts for an invalid strategy id', async () => {
                // create a strategy
                await createStrategy();

                // assert
                await expect(
                    voucher.connect(owner).transferFrom(owner.address, deployer.address, 0)
                ).to.have.been.revertedWithError('ERC721: invalid token ID');
                await expect(
                    voucher.connect(owner).transferFrom(owner.address, deployer.address, SID2)
                ).to.have.been.revertedWithError('ERC721: invalid token ID');
            });

            it('reverts for an invalid target address', async () => {
                // create a strategy
                await createStrategy();

                // assert
                await expect(
                    voucher.connect(owner).transferFrom(owner.address, ZERO_ADDRESS, SID1)
                ).to.have.been.revertedWithError('ERC721: transfer to the zero address');
            });

            it('emits the voucher Transfer event', async () => {
                // create a strategy
                await createStrategy();

                // transfer the voucher
                const tx = voucher.connect(owner).transferFrom(owner.address, nonAdmin.address, SID1);

                // assert
                await expect(tx).to.emit(voucher, 'Transfer').withArgs(owner.address, nonAdmin.address, SID1);
            });
        });

        describe('tokenURI', () => {
            it('generates a global URI', async () => {
                await createStrategy();
                await voucher.setBaseURI('ipfs://test321');
                await voucher.useGlobalURI(true);
                const result = await voucher.tokenURI(SID1);
                expect(result).to.eq('ipfs://test321');
            });

            it('generates a unique URI', async () => {
                await voucher.setBaseURI('ipfs://test123/');
                await voucher.useGlobalURI(false);
                await createStrategy();
                const result = await voucher.tokenURI(SID1);
                expect(result).to.eq(`ipfs://test123/${SID1}`);
            });

            it('generates a unique URI with baseExtension', async () => {
                await voucher.setBaseURI('ipfs://test123/');
                await voucher.setBaseExtension('.json');
                await voucher.useGlobalURI(false);
                await createStrategy();
                const result = await voucher.tokenURI(SID1);
                expect(result).to.eq(`ipfs://test123/${SID1}.json`);
            });
        });

        it('reverts if a transfer occurs before the carbonController was set', async () => {
            const voucher = await createProxy(Contracts.Voucher, {
                initArgs: [true, '', '']
            });
            const carbonController = await createCarbonController(voucher);
            const order = { ...generateTestOrder(), y: BigNumber.from(0) };
            const tx = carbonController.createStrategy(token0.address, token1.address, [order, order]);
            await expect(tx).to.have.been.revertedWithError('AccessDenied');
        });
    });

    it('skips transfers of 0 amount', async () => {
        const { tx } = await createStrategy({ token0, token1, token0Amount: 0, token1Amount: 0 });
        await expect(tx).to.not.emit(token0, 'Transfer');
        await expect(tx).to.not.emit(token1, 'Transfer');
    });

    describe('withdraw fees', () => {
        it('reverts when paused', async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_EMERGENCY_STOPPER, nonAdmin.address);
            await carbonController.connect(nonAdmin).pause();

            const tx = carbonController.withdrawFees(token0.address, 1, nonAdmin.address);
            await expect(tx).to.be.revertedWithError('Pausable: paused');
        });

        it('reverts when the caller is missing the required role', async () => {
            const tx = carbonController.withdrawFees(token0.address, 1, nonAdmin.address);
            await expect(tx).to.be.revertedWithError('AccessDenied');
        });

        it('reverts when the recipient address is invalid', async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, nonAdmin.address);
            const tx = carbonController.connect(nonAdmin).withdrawFees(token0.address, 1, ZERO_ADDRESS);
            await expect(tx).to.be.revertedWithError('InvalidAddress');
        });

        it('reverts when the token address is invalid', async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, nonAdmin.address);
            const tx = carbonController.connect(nonAdmin).withdrawFees(ZERO_ADDRESS, 1, nonAdmin.address);
            await expect(tx).to.be.revertedWithError('InvalidAddress');
        });

        it('reverts when the amount is invalid', async () => {
            await carbonController
                .connect(deployer)
                .grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, nonAdmin.address);
            const tx = carbonController.connect(nonAdmin).withdrawFees(token0.address, 0, nonAdmin.address);
            await expect(tx).to.be.revertedWithError('ZeroValue');
        });

        it('emits the FeesWithdrawn', async () => {
            const amount = BigNumber.from(10);
            await transfer(deployer, token0, carbonController.address, amount);
            const tx = await withdrawFees(amount, amount, token0);

            await expect(tx)
                .to.emit(carbonController, 'FeesWithdrawn')
                .withArgs(token0.address, owner.address, amount.toNumber(), owner.address);
        });

        it("doesn't emit the FeesWithdrawn if accumulated fee amount is 0", async () => {
            const amount = BigNumber.from(1);
            // don't set accumulated fees

            await carbonController.connect(deployer).grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, owner.address);
            const tx = carbonController.connect(owner).withdrawFees(token0.address, amount, owner.address);

            await expect(tx)
                .not.to.emit(carbonController, 'FeesWithdrawn')
                .withArgs(token0.address, owner.address, amount.toNumber(), owner.address);
        });

        it('updates accumulatedFees balance', async () => {
            const amount = BigNumber.from(10);
            await transfer(deployer, token0, carbonController.address, amount);
            await withdrawFees(amount, amount, token0);
            const accumulatedFees = await carbonController.testAccumulatedFees(token0.address);
            expect(accumulatedFees).to.eq(0);
        });

        it('should return the withdrawn fee amount', async () => {
            const amount = BigNumber.from(10);
            await transfer(deployer, token0, carbonController.address, amount);
            await carbonController.testSetAccumulatedFees(token0.address, amount);
            await carbonController.connect(deployer).grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, owner.address);
            const feeAmount = await carbonController
                .connect(owner)
                .callStatic.withdrawFees(token0.address, amount, owner.address);
            expect(feeAmount).to.eq(amount);
        });

        it('should cap the fee amount to the available balance', async () => {
            const feeAmount = BigNumber.from(10);
            const withdrawAmount = feeAmount.add(1);
            await transfer(deployer, token0, carbonController.address, feeAmount);
            await carbonController.testSetAccumulatedFees(token0.address, feeAmount);
            await carbonController.connect(deployer).grantRole(Roles.CarbonController.ROLE_FEES_MANAGER, owner.address);
            const feeReturnAmount = await carbonController
                .connect(owner)
                .callStatic.withdrawFees(token0.address, withdrawAmount, owner.address);
            expect(feeReturnAmount).to.eq(feeAmount);
        });

        async function checkBalancesAreUpdated(token: TokenSymbol, feeAmount: BigNumber, withdrawAmount: BigNumber) {
            // prepare
            const _token = tokens[token];
            await transfer(deployer, _token, carbonController.address, feeAmount);

            const balanceTypes = [
                { type: 'recipient', token: _token, account: owner.address },
                { type: 'controller', token: _token, account: carbonController.address }
            ];

            // fetch balances before withdraw
            const before: any = {};
            for (const b of balanceTypes) {
                before[b.type] = await getBalance(b.token, b.account);
            }

            // perform withdraw
            const tx = await withdrawFees(feeAmount, withdrawAmount, _token);
            const receipt = await tx.wait();
            const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

            // fetch balances after creating
            const after: any = {};
            for (const b of balanceTypes) {
                after[b.type] = await getBalance(b.token, b.account);
            }

            // assert
            const expectedAmountWithGasAccounted =
                _token.address === NATIVE_TOKEN_ADDRESS ? feeAmount.sub(gasUsed) : feeAmount;
            expect(after.recipient).to.eq(before.recipient.add(expectedAmountWithGasAccounted));
            expect(after.controller).to.eq(before.controller.sub(feeAmount));
        }

        describe('balances are updated correctly', () => {
            const _permutations = [{ token: TokenSymbol.TKN0 }, { token: TokenSymbol.ETH }];

            for (const { token } of _permutations) {
                it(`${token}`, async () => {
                    const feeAmount = BigNumber.from(2);
                    const withdrawAmount = BigNumber.from(3);
                    // check withdrawing the available fee amount
                    await checkBalancesAreUpdated(token, feeAmount, feeAmount);
                    // check withdrawing more than the available fee amount
                    await checkBalancesAreUpdated(token, feeAmount, withdrawAmount);
                });
            }
        });
    });
});
