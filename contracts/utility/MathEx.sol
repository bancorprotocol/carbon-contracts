// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/**
 * @dev this library provides a set of complex math operations
 */
library MathEx {
    error Overflow();

    struct Uint512 {
        uint256 hi; // 256 most significant bits
        uint256 lo; // 256 least significant bits
    }

    /**
     * @dev returns the largest integer smaller than or equal to `x * y / z`
     */
    function mulDivF(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        // safe because no `+` or `-` or `*`
        unchecked {
            Uint512 memory xy = _mul512(x, y);

            // if `x * y < 2 ^ 256`
            if (xy.hi == 0) {
                return xy.lo / z;
            }

            // assert `x * y / z < 2 ^ 256`
            if (xy.hi >= z) {
                revert Overflow();
            }

            uint256 m = _mulMod(x, y, z); // `m = x * y % z`
            Uint512 memory n = _sub512(xy, m); // `n = x * y - m` hence `n / z = floor(x * y / z)`

            // if `n < 2 ^ 256`
            if (n.hi == 0) {
                return n.lo / z;
            }

            uint256 p = _unsafeSub(0, z) & z; // `p` is the largest power of 2 which `z` is divisible by
            uint256 q = _div512(n, p); // `n` is divisible by `p` because `n` is divisible by `z` and `z` is divisible by `p`
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
     * @dev returns the value of `x * y`
     */
    function _mul512(uint256 x, uint256 y) private pure returns (Uint512 memory) {
        uint256 p = _mulModMax(x, y);
        uint256 q = _unsafeMul(x, y);
        if (p >= q) {
            unchecked {
                // safe because `p >= q`
                return Uint512({ hi: p - q, lo: q });
            }
        }
        return Uint512({ hi: _unsafeSub(p, q) - 1, lo: q });
    }

    /**
     * @dev returns the value of `x - y`
     */
    function _sub512(Uint512 memory x, uint256 y) private pure returns (Uint512 memory) {
        if (x.lo >= y) {
            unchecked {
                // safe because `x.lo >= y`
                return Uint512({ hi: x.hi, lo: x.lo - y });
            }
        }
        return Uint512({ hi: x.hi - 1, lo: _unsafeSub(x.lo, y) });
    }

    /**
     * @dev returns the value of `x / pow2n`, given that `x` is divisible by `pow2n`
     */
    function _div512(Uint512 memory x, uint256 pow2n) private pure returns (uint256) {
        // safe because no `+` or `-` or `*`
        unchecked {
            uint256 pow2nInv = _unsafeAdd(_unsafeSub(0, pow2n) / pow2n, 1); // `1 << (256 - n)`
            return _unsafeMul(x.hi, pow2nInv) | (x.lo / pow2n); // `(x.hi << (256 - n)) | (x.lo >> n)`
        }
    }

    /**
     * @dev returns the inverse of `d` modulo `2 ^ 256`, given that `d` is congruent to `1` modulo `2`
     */
    function _inv256(uint256 d) private pure returns (uint256) {
        // approximate the root of `f(x) = 1 / x - d` using the newton–raphson convergence method
        uint256 x = 1;
        unchecked {
            // safe because no `i < 8`
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
