// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

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
