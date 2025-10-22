// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract VortexTestCaseParser is Test {
    using stdJson for string;
    using SafeCast for uint256;

    error InvalidVortexTestCaseJson();

    struct PriceAtTimestamp {
        uint128 sourceAmount;
        uint128 targetAmount;
        uint32 timestamp;
    }

    struct PriceAtTimestampString {
        string sourceAmount;
        string targetAmount;
        string timestamp;
    }

    struct TestCase {
        PriceAtTimestamp[] pricesAtTimestamp;
    }

    /**
     * @dev helper function to get test cases by parsing test data json
     */
    function getTestCase() public view returns (TestCase memory testCase) {
        string memory path = "./test/helpers/data/vortexPricingTestData.json"; // same filename
        string memory json = vm.readFile(path);
        testCase = parseTestCase(json, "testCase");
        return testCase;
    }

    /**
     * @dev parse the json object to TestCase[] struct
     */
    function parseTestCase(
        string memory json,
        string memory templateName
    ) private pure returns (TestCase memory testCases) {
        string memory base = string.concat("$.", templateName);

        uint256 testCaseLength = vm.parseJsonUint(json, "$.testCaseCount");
        if (testCaseLength < 1) {
            revert InvalidVortexTestCaseJson();
        }

        // Build the base path for testCase[0]
        string memory parseString = string.concat(base, "[0");

        // Read per-test-case count for tokenPriceAtTimestamps
        uint256 tokenPriceLen = vm.parseJsonUint(json, string.concat(parseString, "].tokenPriceAtTimestampsCount"));

        // Initialize output array
        PriceAtTimestamp[] memory pricesAtTimestamp = new PriceAtTimestamp[](tokenPriceLen);

        // Fill elements
        for (uint256 j = 0; j < tokenPriceLen; ++j) {
            string memory fullParseString = string.concat(parseString, "].tokenPriceAtTimestamps[");
            fullParseString = string.concat(fullParseString, Strings.toString(j));
            fullParseString = string.concat(fullParseString, "]");

            bytes memory tokenPriceAtTimestampBytes = json.parseRaw(fullParseString);
            pricesAtTimestamp[j] = convertPriceAtTimestampToUint(
                abi.decode(tokenPriceAtTimestampBytes, (PriceAtTimestampString))
            );
        }

        testCases.pricesAtTimestamp = pricesAtTimestamp;
        return testCases;
    }

    /// @dev convert a price at timestamp struct to numeric types
    function convertPriceAtTimestampToUint(
        PriceAtTimestampString memory s
    ) private pure returns (PriceAtTimestamp memory r) {
        return
            PriceAtTimestamp({
                timestamp: stringToUint(s.timestamp).toUint32(),
                sourceAmount: stringToUint(s.sourceAmount).toUint128(),
                targetAmount: stringToUint(s.targetAmount).toUint128()
            });
    }

    /// @dev parse a decimal string to uint256
    function stringToUint(string memory m) private pure returns (uint256 result) {
        bytes memory b = bytes(m);
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) result = result * 10 + (c - 48);
        }
    }
}
