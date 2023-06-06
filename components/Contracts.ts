import {
    CarbonController__factory,
    ERC20__factory,
    FeeBurner__factory,
    MockBancorNetworkV3__factory,
    OptimizedTransparentUpgradeableProxy__factory,
    ProxyAdmin__factory,
    TestBNT__factory,
    TestCarbonController__factory,
    TestERC20Burnable__factory,
    TestERC20FeeOnTransfer__factory,
    TestERC20Token__factory,
    TestLogic__factory,
    TestMathEx__factory,
    TestOnlyProxyDelegate__factory,
    TestPairs__factory,
    TestStrategies__factory,
    TestTokenType__factory,
    TestUpgradeable__factory,
    TestVoucher__factory,
    Voucher__factory
} from '../typechain-types';
import { deployOrAttach } from './ContractBuilder';
import { Signer } from 'ethers';

export * from '../typechain-types';

const getContracts = (signer?: Signer) => ({
    connect: (signer: Signer) => getContracts(signer),

    ERC20: deployOrAttach('ERC20', ERC20__factory, signer),
    CarbonController: deployOrAttach('CarbonController', CarbonController__factory, signer),
    FeeBurner: deployOrAttach('FeeBurner', FeeBurner__factory, signer),
    MockBancorNetworkV3: deployOrAttach('MockBancorNetworkV3', MockBancorNetworkV3__factory, signer),
    ProxyAdmin: deployOrAttach('ProxyAdmin', ProxyAdmin__factory, signer),
    Voucher: deployOrAttach('Voucher', Voucher__factory, signer),
    TestERC20FeeOnTransfer: deployOrAttach('TestERC20FeeOnTransfer', TestERC20FeeOnTransfer__factory, signer),
    TestERC20Burnable: deployOrAttach('TestERC20Burnable', TestERC20Burnable__factory, signer),
    TestERC20Token: deployOrAttach('TestERC20Token', TestERC20Token__factory, signer),
    TestBNT: deployOrAttach('TestBNT', TestBNT__factory, signer),
    TestLogic: deployOrAttach('TestLogic', TestLogic__factory, signer),
    TestMathEx: deployOrAttach('TestMathEx', TestMathEx__factory, signer),
    TestStrategies: deployOrAttach('TestStrategies', TestStrategies__factory, signer),
    TestPairs: deployOrAttach('TestPairs', TestPairs__factory, signer),
    TestTokenType: deployOrAttach('TestTokenType', TestTokenType__factory, signer),
    TestUpgradeable: deployOrAttach('TestUpgradeable', TestUpgradeable__factory, signer),
    TestOnlyProxyDelegate: deployOrAttach('TestOnlyProxyDelegate', TestOnlyProxyDelegate__factory, signer),
    TestVoucher: deployOrAttach('TestVoucher', TestVoucher__factory, signer),
    TestCarbonController: deployOrAttach('TestCarbonController', TestCarbonController__factory, signer),
    OptimizedTransparentUpgradeableProxy: deployOrAttach(
        'OptimizedTransparentUpgradeableProxy',
        OptimizedTransparentUpgradeableProxy__factory,
        signer
    )
});

export type ContractsType = ReturnType<typeof getContracts>;

export default getContracts();
