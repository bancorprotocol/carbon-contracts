/* eslint-disable camelcase */
import { Signer } from 'ethers';

const getContracts = (signer?: Signer) => ({
    connect: (signer: Signer) => getContracts(signer)
});

export default getContracts();
