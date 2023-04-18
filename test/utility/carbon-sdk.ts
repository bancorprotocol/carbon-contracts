import Decimal from 'decimal.js';
import { BigNumber } from 'ethers';

const ONE = 2 ** 48;

const BnToDec = (x: BigNumber) => new Decimal(x.toString());
const DecToBn = (x: Decimal) => BigNumber.from(x.toFixed());

function bitLength(value: BigNumber) {
    return value.gt(0) ? Decimal.log2(value.toString()).add(1).floor().toNumber() : 0;
}

function encodeRate(value: Decimal) {
    const data = DecToBn(value.sqrt().mul(ONE).floor());
    const length = bitLength(data.div(ONE));
    return BnToDec(data.shr(length).shl(length));
}

function decodeRate(value: Decimal) {
    return value.div(ONE).pow(2);
}

function encodeFloat(value: BigNumber) {
    const exponent = bitLength(value.div(ONE));
    const mantissa = value.shr(exponent);
    return BigNumber.from(ONE).mul(exponent).or(mantissa);
}

function decodeFloat(value: BigNumber) {
    return value.mod(ONE).shl(value.div(ONE).toNumber());
}

export type DecodedOrder = {
    liquidity: Decimal;
    lowestRate: Decimal;
    highestRate: Decimal;
    marginalRate: Decimal;
};

export type EncodedOrder = {
    y: BigNumber;
    z: BigNumber;
    A: BigNumber;
    B: BigNumber;
};

export const encodeOrder = (order: DecodedOrder): EncodedOrder => {
    const y = DecToBn(order.liquidity);
    const L = DecToBn(encodeRate(order.lowestRate));
    const H = DecToBn(encodeRate(order.highestRate));
    const M = DecToBn(encodeRate(order.marginalRate));
    return {
        y,
        z: H.eq(M) ? y : y.mul(H.sub(L)).div(M.sub(L)),
        A: encodeFloat(H.sub(L)),
        B: encodeFloat(L)
    };
};

export const decodeOrder = (order: EncodedOrder): DecodedOrder => {
    const y = BnToDec(order.y);
    const z = BnToDec(order.z);
    const A = BnToDec(decodeFloat(order.A));
    const B = BnToDec(decodeFloat(order.B));
    return {
        liquidity: y,
        lowestRate: decodeRate(B),
        highestRate: decodeRate(B.add(A)),
        marginalRate: decodeRate(y.eq(z) ? B.add(A) : B.add(A.mul(y).div(z)))
    };
};
