// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { MathEx } from "./MathEx.sol";

library Trade {
    error ExpOverflow();
    error InvalidInitialRate();
    error InvalidMultiFactor();

    uint256 private constant R_ONE = 1 << 48;
    uint256 private constant M_ONE = 1 << 24;

    uint256 private constant EXP_ONE = 1 << 127;
    uint256 private constant MAX_VAL = 1 << 131;

    enum GradientType {
        LINEAR_INCREASE,
        LINEAR_DECREASE,
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
        (uint256 d, uint256 n) = calcCurrentRate(gradientType, initialRate, multiFactor, timeElapsed);
        return MathEx.mulDivC(targetAmount, d, n);
    }

    function calcCurrentRate(
        GradientType gradientType,
        uint64 initialRate,
        uint32 multiFactor,
        uint32 timeElapsed
    ) internal pure returns (uint256, uint256) { unchecked {
        if ((R_ONE >> (initialRate / R_ONE)) == 0) {revert InvalidInitialRate();}
        if ((M_ONE >> (multiFactor / M_ONE)) == 0) {revert InvalidMultiFactor();}
        uint256 r = uint256(initialRate % R_ONE) << (initialRate / R_ONE); // < 2 ^ 96
        uint256 m = uint256(multiFactor % M_ONE) << (multiFactor / M_ONE); // < 2 ^ 48
        uint256 t = uint256(timeElapsed);
        if (gradientType == GradientType.LINEAR_INCREASE) {
            uint256 temp1 = r * r * (m * t + M_ONE * M_ONE);
            uint256 temp2 = M_ONE * M_ONE * R_ONE * R_ONE;
            return (temp1, temp2);
        }
        if (gradientType == GradientType.LINEAR_DECREASE) {
            uint256 temp1 = r * r * M_ONE * M_ONE;
            uint256 temp2 = (m * t + M_ONE * M_ONE) * R_ONE * R_ONE;
            return (temp1, temp2);
        }
        if (gradientType == GradientType.EXPONENTIAL_INCREASE) {
            uint256 temp1 = r * r;
            uint256 temp2 = exp(m * t * EXP_ONE / (M_ONE * M_ONE));
            uint256 temp3 = MathEx.minFactor(temp1, temp2);
            uint256 temp4 = EXP_ONE * R_ONE * R_ONE;
            return (MathEx.mulDivF(temp1, temp2, temp3), temp4 / temp3);
        }
        if (gradientType == GradientType.EXPONENTIAL_DECREASE) {
            uint256 temp1 = r * r;
            uint256 temp2 = EXP_ONE;
            uint256 temp3 = MathEx.minFactor(temp1, temp2);
            uint256 temp4 = exp(m * t * EXP_ONE / (M_ONE * M_ONE)) * R_ONE * R_ONE;
            return (MathEx.mulDivF(temp1, temp2, temp3), temp4 / temp3);
        }
        return (0, 0);
    }}

    /**
      * @dev Compute e ^ (x / EXP_ONE) * EXP_ONE
      * Input range: 0 <= x <= MAX_VAL - 1
      * Detailed description:
      * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
      * - The exponentiation of each binary exponent is given (pre-calculated)
      * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
      * - The exponentiation of the input is calculated by multiplying the intermediate results above
      * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
    */
    function exp(uint256 x) private pure returns (uint256) { unchecked {
        if (x >= MAX_VAL) {
            revert ExpOverflow();
        }

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
    }}
}
