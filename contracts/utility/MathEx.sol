// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Fraction } from "./Fraction.sol";

uint256 constant ONE = 0x80000000000000000000000000000000;
uint256 constant LN2 = 0x58b90bfbe8e7bcd5e4f1d9cc01f97b57;

/**
 * @dev this library provides a set of complex math operations
 */
library MathEx {
    error Overflow();

    /**
     * @dev returns the largest integer smaller than or equal to `x * y / z`
     */
    function mulDivF(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        // safe because no `+` or `-` or `*`
        unchecked {
            (uint256 xyhi, uint256 xylo) = _mul512(x, y);

            // if `x * y < 2 ^ 256`
            if (xyhi == 0) {
                return xylo / z;
            }

            // assert `x * y / z < 2 ^ 256`
            if (xyhi >= z) {
                revert Overflow();
            }

            uint256 m = _mulMod(x, y, z); // `m = x * y % z`
            (uint256 nhi, uint256 nlo) = _sub512(xyhi, xylo, m); // `n = x * y - m` hence `n / z = floor(x * y / z)`

            // if `n < 2 ^ 256`
            if (nhi == 0) {
                return nlo / z;
            }

            uint256 p = _unsafeSub(0, z) & z; // `p` is the largest power of 2 which `z` is divisible by
            uint256 q = _div512(nhi, nlo, p); // `n` is divisible by `p` because `n` is divisible by `z` and `z` is divisible by `p`
            uint256 r = _inv256(z / p); // `z / p = 1 mod 2` hence `inverse(z / p) = 1 mod 2 ^ 256`
            return _unsafeMul(q, r); // `q * r = (n / p) * inverse(z / p) = n / z`
        }
    }

    /**
     * @dev returns the smallest integer larger than or equal to `x * y / z`
     */
    function mulDivC(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        uint256 w = mulDivF(x, y, z);
        if (_mulMod(x, y, z) > 0) {
            if (w >= type(uint256).max) {
                revert Overflow();
            }
            unchecked {
                // safe because `w < type(uint256).max`
                return w + 1;
            }
        }
        return w;
    }

    /**
     * @dev returns the smallest integer `z` such that `x * y / z <= 2 ^ 256 - 1`
     */
    function minFactor(uint256 x, uint256 y) internal pure returns (uint256) {
        (uint256 hi, uint256 lo) = _mul512(x, y);
        unchecked {
            // safe because:
            // - if `x < 2 ^ 256 - 1` or `y < 2 ^ 256 - 1`
            //   then `hi < 2 ^ 256 - 2`
            //   hence neither `hi + 1` nor `hi + 2` overflows
            // - if `x = 2 ^ 256 - 1` and `y = 2 ^ 256 - 1`
            //   then `hi = 2 ^ 256 - 2 = ~lo`
            //   hence `hi + 1`, which does not overflow, is computed
            return hi > ~lo ? hi + 2 : hi + 1;
        }

        /* reasoning:
        |
        |   general:
        |   - find the smallest integer `z` such that `x * y / z <= 2 ^ 256 - 1`
        |   - the value of `x * y` is represented via `2 ^ 256 * hi + lo`
        |   - the expression `~lo` is equivalent to `2 ^ 256 - 1 - lo`
        |   
        |   symbols:
        |   - let `H` denote `hi`
        |   - let `L` denote `lo`
        |   - let `N` denote `2 ^ 256 - 1`
        |   
        |   inference:
        |   `x * y / z <= 2 ^ 256 - 1`     <-->
        |   `x * y / (2 ^ 256 - 1) <= z`   <-->
        |   `((N + 1) * H + L) / N <= z`   <-->
        |   `(N * H + H + L) / N <= z`     <-->
        |   `H + (H + L) / N <= z`
        |   
        |   inference:
        |   `0 <= H <= N && 0 <= L <= N`   <-->
        |   `0 <= H + L <= N + N`          <-->
        |   `0 <= H + L <= N * 2`          <-->
        |   `0 <= (H + L) / N <= 2`
        |   
        |   inference:
        |   - `0 = (H + L) / N` --> `H + L = 0` --> `x * y = 0` --> `z = 1 = H + 1`
        |   - `0 < (H + L) / N <= 1` --> `H + (H + L) / N <= H + 1` --> `z = H + 1`
        |   - `1 < (H + L) / N <= 2` --> `H + (H + L) / N <= H + 2` --> `z = H + 2`
        |   
        |   implementation:
        |   - if `hi > ~lo`:
        |     `~L < H <= N`                         <-->
        |     `N - L < H <= N`                      <-->
        |     `N < H + L <= N + L`                  <-->
        |     `1 < (H + L) / N <= 2`                <-->
        |     `H + 1 < H + (H + L) / N <= H + 2`    <-->
        |     `z = H + 2`
        |   - if `hi <= ~lo`:
        |     `H <= ~L`                             <-->
        |     `H <= N - L`                          <-->
        |     `H + L <= N`                          <-->
        |     `(H + L) / N <= 1`                    <-->
        |     `H + (H + L) / N <= H + 1`            <-->
        |     `z = H + 1`
        |
        */
    }

    /**
     * @dev returns `2 ^ f` by calculating `e ^ (f * ln(2))`, where `e` is Euler's number:
     * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
     * - The exponentiation of each binary exponent is given (pre-calculated)
     * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
     * - The exponentiation of the input is calculated by multiplying the intermediate results above
     * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
     */
    function exp2(Fraction memory f) internal pure returns (Fraction memory) {
        uint256 x = MathEx.mulDivF(LN2, f.n, f.d);
        uint256 y;
        uint256 z;
        uint256 n;

        if (x >= (ONE << 4)) {
            revert Overflow();
        }

        unchecked {
            z = y = x % (ONE >> 3); // get the input modulo 2^(-3)
            z = (z * y) / ONE;
            n += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
            z = (z * y) / ONE;
            n += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
            z = (z * y) / ONE;
            n += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
            z = (z * y) / ONE;
            n += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
            z = (z * y) / ONE;
            n += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
            z = (z * y) / ONE;
            n += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
            z = (z * y) / ONE;
            n += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
            z = (z * y) / ONE;
            n += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
            z = (z * y) / ONE;
            n += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
            z = (z * y) / ONE;
            n += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
            z = (z * y) / ONE;
            n += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
            z = (z * y) / ONE;
            n += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
            z = (z * y) / ONE;
            n += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
            z = (z * y) / ONE;
            n += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
            z = (z * y) / ONE;
            n += z * 0x000000000001c638; // add y^16 * (20! / 16!)
            z = (z * y) / ONE;
            n += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
            z = (z * y) / ONE;
            n += z * 0x000000000000017c; // add y^18 * (20! / 18!)
            z = (z * y) / ONE;
            n += z * 0x0000000000000014; // add y^19 * (20! / 19!)
            z = (z * y) / ONE;
            n += z * 0x0000000000000001; // add y^20 * (20! / 20!)
            n = n / 0x21c3677c82b40000 + y + ONE; // divide by 20! and then add y^1 / 1! + y^0 / 0!

            if ((x & (ONE >> 3)) != 0)
                n = (n * 0x1c3d6a24ed82218787d624d3e5eba95f9) / 0x18ebef9eac820ae8682b9793ac6d1e776; // multiply by e^(2^-3)
            if ((x & (ONE >> 2)) != 0)
                n = (n * 0x18ebef9eac820ae8682b9793ac6d1e778) / 0x1368b2fc6f9609fe7aceb46aa619baed4; // multiply by e^(2^-2)
            if ((x & (ONE >> 1)) != 0)
                n = (n * 0x1368b2fc6f9609fe7aceb46aa619baed5) / 0x0bc5ab1b16779be3575bd8f0520a9f21f; // multiply by e^(2^-1)
            if ((x & (ONE << 0)) != 0)
                n = (n * 0x0bc5ab1b16779be3575bd8f0520a9f21e) / 0x0454aaa8efe072e7f6ddbab84b40a55c9; // multiply by e^(2^+0)
            if ((x & (ONE << 1)) != 0)
                n = (n * 0x0454aaa8efe072e7f6ddbab84b40a55c5) / 0x00960aadc109e7a3bf4578099615711ea; // multiply by e^(2^+1)
            if ((x & (ONE << 2)) != 0)
                n = (n * 0x00960aadc109e7a3bf4578099615711d7) / 0x0002bf84208204f5977f9a8cf01fdce3d; // multiply by e^(2^+2)
            if ((x & (ONE << 3)) != 0)
                n = (n * 0x0002bf84208204f5977f9a8cf01fdc307) / 0x0000003c6ab775dd0b95b4cbee7e65d11; // multiply by e^(2^+3)
        }

        return Fraction({ n: n, d: ONE });
    }

    /**
     * @dev returns the value of `x * y`
     */
    function _mul512(uint256 x, uint256 y) private pure returns (uint256, uint256) {
        uint256 p = _mulModMax(x, y);
        uint256 q = _unsafeMul(x, y);
        if (p >= q) {
            unchecked {
                // safe because `p >= q`
                return (p - q, q);
            }
        }
        unchecked {
            // safe because `p < q` hence `_unsafeSub(p, q) > 0`
            return (_unsafeSub(p, q) - 1, q);
        }
    }

    /**
     * @dev returns the value of `x - y`
     */
    function _sub512(uint256 xhi, uint256 xlo, uint256 y) private pure returns (uint256, uint256) {
        if (xlo >= y) {
            unchecked {
                // safe because `xlo >= y`
                return (xhi, xlo - y);
            }
        }
        return (xhi - 1, _unsafeSub(xlo, y));
    }

    /**
     * @dev returns the value of `x / pow2n`, given that `x` is divisible by `pow2n`
     */
    function _div512(uint256 xhi, uint256 xlo, uint256 pow2n) private pure returns (uint256) {
        // safe because no `+` or `-` or `*`
        unchecked {
            uint256 pow2nInv = _unsafeAdd(_unsafeSub(0, pow2n) / pow2n, 1); // `1 << (256 - n)`
            return _unsafeMul(xhi, pow2nInv) | (xlo / pow2n); // `(xhi << (256 - n)) | (xlo >> n)`
        }
    }

    /**
     * @dev returns the inverse of `d` modulo `2 ^ 256`, given that `d` is congruent to `1` modulo `2`
     */
    function _inv256(uint256 d) private pure returns (uint256) {
        // approximate the root of `f(x) = 1 / x - d` using the newton–raphson convergence method
        uint256 x = 1;
        unchecked {
            // safe because `i < 8`
            for (uint256 i = 0; i < 8; i++) {
                x = _unsafeMul(x, _unsafeSub(2, _unsafeMul(x, d))); // `x = x * (2 - x * d) mod 2 ^ 256`
            }
        }
        return x;
    }

    /**
     * @dev returns `(x + y) % 2 ^ 256`
     */
    function _unsafeAdd(uint256 x, uint256 y) private pure returns (uint256) {
        unchecked {
            return x + y;
        }
    }

    /**
     * @dev returns `(x - y) % 2 ^ 256`
     */
    function _unsafeSub(uint256 x, uint256 y) private pure returns (uint256) {
        unchecked {
            return x - y;
        }
    }

    /**
     * @dev returns `(x * y) % 2 ^ 256`
     */
    function _unsafeMul(uint256 x, uint256 y) private pure returns (uint256) {
        unchecked {
            return x * y;
        }
    }

    /**
     * @dev returns `x * y % (2 ^ 256 - 1)`
     */
    function _mulModMax(uint256 x, uint256 y) private pure returns (uint256) {
        return mulmod(x, y, type(uint256).max);
    }

    /**
     * @dev returns `x * y % z`
     */
    function _mulMod(uint256 x, uint256 y, uint256 z) private pure returns (uint256) {
        return mulmod(x, y, z);
    }
}
