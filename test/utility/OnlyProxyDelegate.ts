import Contracts from '../../components/Contracts';
import { ZERO_ADDRESS } from '../../utils/Constants';
import { NATIVE_TOKEN_ADDRESS } from '../../utils/TokenData';
import { expect } from 'chai';

describe('OnlyProxyDelegate', () => {
    it('reverts when the proxy address was not set', async () => {
        const testOnlyProxyDelegate = await Contracts.TestOnlyProxyDelegate.deploy(ZERO_ADDRESS);
        const tx = testOnlyProxyDelegate.testOnlyProxyDelegate();
        await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
    });

    it('reverts when the address provided is not equal to the proxy', async () => {
        const testOnlyProxyDelegate = await Contracts.TestOnlyProxyDelegate.deploy(NATIVE_TOKEN_ADDRESS);
        const tx = testOnlyProxyDelegate.testOnlyProxyDelegate();
        await expect(tx).to.have.been.revertedWithError('UnknownDelegator');
    });
});
