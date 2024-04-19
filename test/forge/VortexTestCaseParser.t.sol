// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract VortexTestCaseParser is Test {
    using stdJson for string;
    using SafeCast for uint256;

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
        string memory path = "./test/helpers/data/vortexPricingTestData.json";
        string memory json = vm.readFile(path);
        testCase = parseTestCase(json, "testCase");

        return testCase;
    }

    /**
     * @dev helper function to parse test data json object to TestCase struct
     */
    function parseTestCase(
        string memory json,
        string memory templateName
    ) private pure returns (TestCase memory testCases) {
        string memory initialParseString = string.concat("$.", templateName);

        // read the test case length
        string[] memory testCaseString = vm.parseJsonStringArray(json, initialParseString);
        uint256 testCaseLength = testCaseString.length;

        initialParseString = string.concat(initialParseString, "[");

        for (uint256 i = 0; i < testCaseLength; ++i) {
            // get the correct testCase index to parse
            string memory parseString = string.concat(initialParseString, Strings.toString(i));

            // Decode the different prices at each timestamp

            // read the timestamp case length
            string[] memory tokenPriceString = vm.parseJsonStringArray(
                json,
                string.concat(parseString, "].tokenPriceAtTimestamps")
            );
            uint256 tokenPriceLen = tokenPriceString.length;

            // initialize token price at timestamp string length
            PriceAtTimestamp[] memory pricesAtTimestamp = new PriceAtTimestamp[](tokenPriceLen);

            // fill in the token price at timestamp
            for (uint256 j = 0; j < tokenPriceLen; ++j) {
                // Parse the token price field into a bytes array
                string memory fullParseString = string.concat(parseString, "].tokenPriceAtTimestamps[");
                fullParseString = string.concat(fullParseString, Strings.toString(j));
                fullParseString = string.concat(fullParseString, "]");
                bytes memory tokenPriceAtTimestampBytes = json.parseRaw(fullParseString);
                pricesAtTimestamp[j] = convertPriceAtTimestampToUint(
                    abi.decode(tokenPriceAtTimestampBytes, (PriceAtTimestampString))
                );
            }

            testCases.pricesAtTimestamp = pricesAtTimestamp;
        }
        return testCases;
    }

    /// @dev convert a price at timestamp struct to uint256
    function convertPriceAtTimestampToUint(
        PriceAtTimestampString memory priceAtTimestampString
    ) private pure returns (PriceAtTimestamp memory priceAtTimestamp) {
        return
            PriceAtTimestamp({
                timestamp: stringToUint(priceAtTimestampString.timestamp).toUint32(),
                sourceAmount: stringToUint(priceAtTimestampString.sourceAmount).toUint128(),
                targetAmount: stringToUint(priceAtTimestampString.targetAmount).toUint128()
            });
    }

    /// @dev helper function to convert a string to uint256
    function stringToUint(string memory s) private pure returns (uint256 result) {
        bytes memory b = bytes(s);
        result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }
}
