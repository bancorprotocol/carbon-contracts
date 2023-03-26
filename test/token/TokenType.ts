import Contracts, { TestTokenType } from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { NATIVE_TOKEN_ADDRESS, TokenData, TokenSymbol } from '../../utils/TokenData';
import { createToken } from '../helpers/Factory';
import { getBalance, transfer } from '../helpers/Utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('TokenType', () => {
    const TOTAL_SUPPLY = 1_000_000;

    let tokenType: TestTokenType;

    let deployer: SignerWithAddress;
    let recipient: SignerWithAddress;
    let spender: SignerWithAddress;

    before(async () => {
        [deployer, recipient, spender] = await ethers.getSigners();
    });

    beforeEach(async () => {
        tokenType = await Contracts.TestTokenType.deploy();
    });

    for (const symbol of [TokenSymbol.ETH, TokenSymbol.TKN]) {
        let token: any;
        const tokenData = new TokenData(symbol);

        context(`${symbol} reserve token`, () => {
            beforeEach(async () => {
                token = await createToken(tokenData, TOTAL_SUPPLY);
            });

            it('should properly check if the reserve token is a native token', async () => {
                expect(await tokenType.isNative(token.address)).to.equal(tokenData.isNative());
            });

            it('should properly get the right symbol', async () => {
                expect(await tokenType.symbol(token.address)).to.equal(symbol);
            });

            it('should properly get the right decimals', async () => {
                if (tokenData.isNative()) {
                    expect(await tokenType.decimals(token.address)).to.equal(tokenData.decimals());
                } else {
                    const decimals = await token.decimals();
                    expect(await tokenType.decimals(token.address)).to.equal(decimals);

                    const decimals2 = 4;
                    await token.updateDecimals(decimals2);
                    expect(await tokenType.decimals(token.address)).to.equal(decimals2);
                }
            });

            it('should properly get the right balance', async () => {
                expect(await tokenType.balanceOf(token.address, deployer.address)).to.equal(
                    await getBalance(token, deployer)
                );
            });

            for (const amount of [0, 10_000]) {
                beforeEach(async () => {
                    await transfer(deployer, token, tokenType.address, amount);
                });

                it('should properly transfer the reserve token', async () => {
                    const prevLibraryBalance = await getBalance(token, tokenType.address);
                    const prevRecipientBalance = await getBalance(token, recipient);

                    await tokenType.safeTransfer(token.address, recipient.address, amount);

                    expect(await getBalance(token, tokenType.address)).to.equal(prevLibraryBalance.sub(amount));
                    expect(await getBalance(token, recipient)).to.equal(prevRecipientBalance.add(amount));
                });
            }

            if (tokenData.isNative()) {
                it('should ignore the request to transfer the reserve token on behalf of a different account using safe approve', async () => {
                    const prevLibraryBalance = await getBalance(token, tokenType.address);
                    const prevRecipientBalance = await getBalance(token, recipient);

                    const amount = 100_000;
                    await tokenType.safeApprove(token.address, tokenType.address, amount);
                    await tokenType.safeTransferFrom(token.address, tokenType.address, recipient.address, amount);

                    expect(await getBalance(token, tokenType.address)).to.equal(prevLibraryBalance);
                    expect(await getBalance(token, recipient)).to.equal(prevRecipientBalance);
                });

                it('should ignore the request to transfer the reserve token on behalf of a different account using ensure approve', async () => {
                    const prevLibraryBalance = await getBalance(token, tokenType.address);
                    const prevRecipientBalance = await getBalance(token, recipient);

                    const amount = 100_000;
                    await tokenType.ensureApprove(token.address, tokenType.address, amount);
                    await tokenType.safeTransferFrom(token.address, tokenType.address, recipient.address, amount);

                    expect(await getBalance(token, tokenType.address)).to.equal(prevLibraryBalance);
                    expect(await getBalance(token, recipient)).to.equal(prevRecipientBalance);
                });
            } else {
                for (const amount of [0, 10_000]) {
                    beforeEach(async () => {
                        await transfer(deployer, token, tokenType.address, amount);
                    });

                    it('should properly transfer the reserve token on behalf of a different account using safe approve', async () => {
                        const prevLibraryBalance = await getBalance(token, tokenType.address);
                        const prevRecipientBalance = await getBalance(token, recipient);

                        await tokenType.safeApprove(token.address, tokenType.address, amount);
                        await tokenType.safeTransferFrom(token.address, tokenType.address, recipient.address, amount);

                        expect(await getBalance(token, tokenType.address)).to.equal(prevLibraryBalance.sub(amount));
                        expect(await getBalance(token, recipient)).to.equal(prevRecipientBalance.add(amount));
                    });

                    it('should properly transfer the reserve token on behalf of a different account using ensure approve', async () => {
                        const prevLibraryBalance = await getBalance(token, tokenType.address);
                        const prevRecipientBalance = await getBalance(token, recipient);

                        await tokenType.ensureApprove(token.address, tokenType.address, amount);
                        await tokenType.safeTransferFrom(token.address, tokenType.address, recipient.address, amount);

                        expect(await getBalance(token, tokenType.address)).to.equal(prevLibraryBalance.sub(amount));
                        expect(await getBalance(token, recipient)).to.equal(prevRecipientBalance.add(amount));
                    });
                }

                it('should allow setting the allowance using safe approve', async () => {
                    const allowance = 1_000_000;

                    await tokenType.safeApprove(token.address, spender.address, allowance);

                    expect(await token.allowance(tokenType.address, spender.address)).to.equal(allowance);
                });

                it('should allow setting the allowance using ensure approve', async () => {
                    const allowance = 1_000_000;

                    await tokenType.ensureApprove(token.address, spender.address, allowance);

                    expect(await token.allowance(tokenType.address, spender.address)).to.equal(allowance);
                });
            }

            it('should compare', async () => {
                expect(await tokenType.isEqual(token.address, token.address)).to.be.true;
                expect(await tokenType.isEqual(token.address, ZERO_ADDRESS)).to.be.false;

                expect(await tokenType.isEqual(token.address, NATIVE_TOKEN_ADDRESS)).to.equal(tokenData.isNative());
            });
        });
    }
});
