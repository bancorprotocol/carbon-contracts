import { defaults } from 'lodash';

export const DEFAULT_DECIMALS = 18;
export const NATIVE_TOKEN_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

export enum TokenSymbol {
    ETH = 'ETH',
    BNT = 'BNT',
    USDC = 'USDC',
    DAI = 'DAI',
    WBTC = 'wBTC',
    TKN = 'TKN',
    TKN0 = 'TKN0',
    TKN1 = 'TKN1',
    TKN2 = 'TKN2'
}

interface Errors {
    exceedsAllowance?: string;
    exceedsBalance?: string;
    burnExceedsBalance?: string;
}

const DEFAULT_ERRORS: Errors = {
    exceedsAllowance: 'ERC20: insufficient allowance',
    exceedsBalance: 'ERC20: transfer amount exceeds balance',
    burnExceedsBalance: 'ERC20: burn amount exceeds balance'
};

const TOKEN_DATA = {
    [TokenSymbol.ETH]: {
        name: 'Ethereum',
        decimals: DEFAULT_DECIMALS,
        errors: {
            exceedsBalance: 'Address: insufficient balance'
        }
    },
    [TokenSymbol.BNT]: {
        name: 'Bancor Network Token',
        decimals: DEFAULT_DECIMALS,
        errors: DEFAULT_ERRORS
    },
    [TokenSymbol.USDC]: {
        name: 'USDC Token',
        decimals: 6,
        errors: DEFAULT_ERRORS
    },
    [TokenSymbol.TKN]: {
        name: 'Test Token',
        decimals: DEFAULT_DECIMALS,
        errors: DEFAULT_ERRORS
    },
    [TokenSymbol.TKN0]: {
        name: 'Test Token 0',
        decimals: DEFAULT_DECIMALS,
        errors: DEFAULT_ERRORS
    },
    [TokenSymbol.TKN1]: {
        name: 'Test Token 1',
        decimals: DEFAULT_DECIMALS,
        errors: DEFAULT_ERRORS
    },
    [TokenSymbol.TKN2]: {
        name: 'Test Token 2',
        decimals: DEFAULT_DECIMALS,
        errors: DEFAULT_ERRORS
    }
};

export class TokenData {
    private readonly _symbol: TokenSymbol;
    private readonly _name: string;
    private readonly _decimals: number;
    private readonly _errors: Errors;

    constructor(symbol: TokenSymbol) {
        this._symbol = symbol;

        const { name, decimals, errors } = TOKEN_DATA[symbol];
        this._name = name;
        this._decimals = decimals;
        this._errors = errors;
    }

    name() {
        return this._name;
    }

    symbol() {
        return this._symbol;
    }

    decimals() {
        return this._decimals;
    }

    errors() {
        return defaults(this._errors, { exceedsAllowance: '', exceedsBalance: '', burnExceedsBalance: '' });
    }

    isDefaultDecimals() {
        return this._decimals === DEFAULT_DECIMALS;
    }

    isNative() {
        return this._symbol === TokenSymbol.ETH;
    }
}
