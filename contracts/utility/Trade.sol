// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { MathEx } from "./MathEx.sol";

library Trade {
    error ExpOverflow();
    error InvalidRate();
    error InitialRateTooHigh();
    error MultiFactorTooHigh();

    uint256 private constant EXP_LN2 = 0x0058b90bfbe8e7bcd5e4f1d9cc01f97b58; // ceil(ln2)
    uint256 private constant EXP_ONE = 0x0080000000000000000000000000000000; // 1
    uint256 private constant EXP_MID = 0x0800000000000000000000000000000000; // 16
    uint256 private constant EXP_MAX = 0x2cb53f09f05cc627c85ddebfccfeb72758; // ceil(ln2) * 129

    uint256 private constant R_ONE = 1 << 48; // = 2 ^ 48
    uint256 private constant M_ONE = 1 << 24; // = 2 ^ 24

    uint256 private constant RR = R_ONE * R_ONE; // = 2 ^ 96
    uint256 private constant MM = M_ONE * M_ONE; // = 2 ^ 48

    uint256 private constant RR_MUL_MM = RR * MM; // = 2 ^ 144
    uint256 private constant RR_DIV_MM = RR / MM; // = 2 ^ 48

    uint256 private constant EXP_ONE_MUL_RR = EXP_ONE * RR; // = 2 ^ 223
    uint256 private constant EXP_ONE_DIV_RR = EXP_ONE / RR; // = 2 ^ 31
    uint256 private constant EXP_ONE_DIV_MM = EXP_ONE / MM; // = 2 ^ 79

    enum GradientType {
        LINEAR_INCREASE,
        LINEAR_DECREASE,
        LINEAR_INV_INCREASE,
        LINEAR_INV_DECREASE,
        EXPONENTIAL_INCREASE,
        EXPONENTIAL_DECREASE
    }

    function calcTargetAmount(
        GradientType gradientType,
        uint64 initialRate,
        uint32 multiFactor,
        uint32 timeElapsed,
        uint256 sourceAmount
    ) internal pure returns (uint256) {
        (uint256 n, uint256 d) = calcCurrentRate(gradientType, initialRate, multiFactor, timeElapsed);
        return MathEx.mulDivF(sourceAmount, n, d);
    }

    function calcSourceAmount(
        GradientType gradientType,
        uint64 initialRate,
        uint32 multiFactor,
        uint32 timeElapsed,
        uint256 targetAmount
    ) internal pure returns (uint256) {
        (uint256 n, uint256 d) = calcCurrentRate(gradientType, initialRate, multiFactor, timeElapsed);
        return MathEx.mulDivC(targetAmount, d, n);
    }

    /**
     * @dev Given the following parameters:
     * r - the gradient's initial exchange rate
     * m - the gradient's multiplication factor
     * t - the time elapsed since strategy creation
     *
     * Calculate the current exchange rate for each one of the following gradients:
     * +----------------+-----------+-----------------+----------------------------------------------+
     * | type           | direction | formula         | restriction                                  |
     * +----------------+-----------+-----------------+----------------------------------------------+
     * | linear         | increase  | r * (1 + m * t) |                                              |
     * | linear         | decrease  | r * (1 - m * t) | m * t < 1 (ensure a finite-positive rate)    |
     * | linear-inverse | increase  | r / (1 - m * t) | m * t < 1 (ensure a finite-positive rate)    |
     * | linear-inverse | decrease  | r / (1 + m * t) |                                              |
     * | exponential    | increase  | r * e ^ (m * t) | m * t < 129 * ln2 (computational limitation) |
     * | exponential    | decrease  | r / e ^ (m * t) | m * t < 129 * ln2 (computational limitation) |
     * +----------------+-----------+-----------------+----------------------------------------------+
     */
    function calcCurrentRate(
        GradientType gradientType,
        uint64 initialRate, // the 48-bit-mantissa-6-bit-exponent encoding of the initial exchange rate square root
        uint32 multiFactor, // the 24-bit-mantissa-5-bit-exponent encoding of the multiplication factor times 2 ^ 24
        uint32 timeElapsed /// the time elapsed since strategy creation
    ) internal pure returns (uint256, uint256) {
        unchecked {
            if ((R_ONE >> (initialRate / R_ONE)) == 0) {
                revert InitialRateTooHigh();
            }

            if ((M_ONE >> (multiFactor / M_ONE)) == 0) {
                revert MultiFactorTooHigh();
            }

            uint256 r = uint256(initialRate % R_ONE) << (initialRate / R_ONE); // = floor(sqrt(initial_rate) * 2 ^ 48)    < 2 ^ 96
            uint256 m = uint256(multiFactor % M_ONE) << (multiFactor / M_ONE); // = floor(multi_factor * 2 ^ 24 * 2 ^ 24) < 2 ^ 48
            uint256 t = uint256(timeElapsed);

            uint256 rr = r * r; // < 2 ^ 192
            uint256 mt = m * t; // < 2 ^ 80

            if (gradientType == GradientType.LINEAR_INCREASE) {
                // initial_rate * (1 + multi_factor * time_elapsed)
                uint256 temp1 = rr; /////// < 2 ^ 192
                uint256 temp2 = MM + mt; // < 2 ^ 81
                uint256 temp3 = MathEx.minFactor(temp1, temp2);
                uint256 temp4 = RR_MUL_MM;
                return (MathEx.mulDivF(temp1, temp2, temp3), temp4 / temp3); // not ideal
            }

            if (gradientType == GradientType.LINEAR_DECREASE) {
                // initial_rate * (1 - multi_factor * time_elapsed)
                uint256 temp1 = rr * sub(MM, mt); // < 2 ^ 240
                uint256 temp2 = RR_MUL_MM;
                return (temp1, temp2);
            }

            if (gradientType == GradientType.LINEAR_INV_INCREASE) {
                // initial_rate / (1 - multi_factor * time_elapsed)
                uint256 temp1 = rr;
                uint256 temp2 = sub(RR, mt * RR_DIV_MM); // < 2 ^ 128 (inner expression)
                return (temp1, temp2);
            }

            if (gradientType == GradientType.LINEAR_INV_DECREASE) {
                // initial_rate / (1 + multi_factor * time_elapsed)
                uint256 temp1 = rr;
                uint256 temp2 = RR + mt * RR_DIV_MM; // < 2 ^ 129
                return (temp1, temp2);
            }

            if (gradientType == GradientType.EXPONENTIAL_INCREASE) {
                // initial_rate * e ^ (multi_factor * time_elapsed)
                uint256 temp1 = rr; //////////////////////// < 2 ^ 192
                uint256 temp2 = exp(mt * EXP_ONE_DIV_MM); // < 2 ^ 159 (inner expression)
                uint256 temp3 = MathEx.minFactor(temp1, temp2);
                uint256 temp4 = EXP_ONE_MUL_RR;
                return (MathEx.mulDivF(temp1, temp2, temp3), temp4 / temp3); // not ideal
            }

            if (gradientType == GradientType.EXPONENTIAL_DECREASE) {
                // initial_rate / e ^ (multi_factor * time_elapsed)
                uint256 temp1 = rr * EXP_ONE_DIV_RR; /////// < 2 ^ 223
                uint256 temp2 = exp(mt * EXP_ONE_DIV_MM); // < 2 ^ 159 (inner expression)
                return (temp1, temp2);
            }

            return (0, 0);
        }
    }

    function sub(uint256 one, uint256 mt) internal pure returns (uint256) {
        unchecked {
            if (one <= mt) {
                revert InvalidRate();
            }
            return one - mt;
        }
    }

    /**
     * @dev Compute e ^ (x / EXP_ONE) * EXP_ONE
     * Input range: 0 <= x <= EXP_MAX - 1
     * Detailed description:
     * - For x < EXP_MID, this function computes e ^ x
     * - For x < EXP_MAX, this function computes e ^ mod(x, ln2) * 2 ^ div(x, ln2)
     * - The latter relies on the following identity:
     *   e ^ x =
     *   e ^ x * 2 ^ k / 2 ^ k =
     *   e ^ x * 2 ^ k / e ^ (k * ln2) =
     *   e ^ x / e ^ (k * ln2) * 2 ^ k =
     *   e ^ (x - k * ln2) * 2 ^ k
     * - Replacing k with div(x, ln2) gives the solution above
     * - The value of ln2 is represented as ceil(ln2 * EXP_ONE)
     */
    function exp(uint256 x) internal pure returns (uint256) {
        unchecked {
            if (x < EXP_MID) {
                return _exp(x);
            }
            if (x < EXP_MAX) {
                return _exp(x % EXP_LN2) << (x / EXP_LN2);
            }
            revert ExpOverflow();
        }
    }

    /**
     * @dev Compute e ^ (x / EXP_ONE) * EXP_ONE
     * Input range: 0 <= x <= EXP_MID - 1
     * Detailed description:
     * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
     * - The exponentiation of each binary exponent is given (pre-calculated)
     * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
     * - The exponentiation of the input is calculated by multiplying the intermediate results above
     * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
     */
    function _exp(uint256 x) private pure returns (uint256) {
        // prettier-ignore
        unchecked {
            uint256 res = 0;

            uint256 y;
            uint256 z;

            z = y = x % 0x10000000000000000000000000000000; // get the input modulo 2^(-3)
            z = z * y / EXP_ONE; res += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
            z = z * y / EXP_ONE; res += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
            z = z * y / EXP_ONE; res += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
            z = z * y / EXP_ONE; res += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
            z = z * y / EXP_ONE; res += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
            z = z * y / EXP_ONE; res += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
            z = z * y / EXP_ONE; res += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
            z = z * y / EXP_ONE; res += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
            z = z * y / EXP_ONE; res += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
            z = z * y / EXP_ONE; res += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
            z = z * y / EXP_ONE; res += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
            z = z * y / EXP_ONE; res += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
            z = z * y / EXP_ONE; res += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
            z = z * y / EXP_ONE; res += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
            z = z * y / EXP_ONE; res += z * 0x000000000001c638; // add y^16 * (20! / 16!)
            z = z * y / EXP_ONE; res += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
            z = z * y / EXP_ONE; res += z * 0x000000000000017c; // add y^18 * (20! / 18!)
            z = z * y / EXP_ONE; res += z * 0x0000000000000014; // add y^19 * (20! / 19!)
            z = z * y / EXP_ONE; res += z * 0x0000000000000001; // add y^20 * (20! / 20!)
            res = res / 0x21c3677c82b40000 + y + EXP_ONE; // divide by 20! and then add y^1 / 1! + y^0 / 0!

            if ((x & 0x010000000000000000000000000000000) != 0) res = res * 0x1c3d6a24ed82218787d624d3e5eba95f9 / 0x18ebef9eac820ae8682b9793ac6d1e776; // multiply by e^2^(-3)
            if ((x & 0x020000000000000000000000000000000) != 0) res = res * 0x18ebef9eac820ae8682b9793ac6d1e778 / 0x1368b2fc6f9609fe7aceb46aa619baed4; // multiply by e^2^(-2)
            if ((x & 0x040000000000000000000000000000000) != 0) res = res * 0x1368b2fc6f9609fe7aceb46aa619baed5 / 0x0bc5ab1b16779be3575bd8f0520a9f21f; // multiply by e^2^(-1)
            if ((x & 0x080000000000000000000000000000000) != 0) res = res * 0x0bc5ab1b16779be3575bd8f0520a9f21e / 0x0454aaa8efe072e7f6ddbab84b40a55c9; // multiply by e^2^(+0)
            if ((x & 0x100000000000000000000000000000000) != 0) res = res * 0x0454aaa8efe072e7f6ddbab84b40a55c5 / 0x00960aadc109e7a3bf4578099615711ea; // multiply by e^2^(+1)
            if ((x & 0x200000000000000000000000000000000) != 0) res = res * 0x00960aadc109e7a3bf4578099615711d7 / 0x0002bf84208204f5977f9a8cf01fdce3d; // multiply by e^2^(+2)
            if ((x & 0x400000000000000000000000000000000) != 0) res = res * 0x0002bf84208204f5977f9a8cf01fdc307 / 0x0000003c6ab775dd0b95b4cbee7e65d11; // multiply by e^2^(+3)

            return res;
        }
    }
}
