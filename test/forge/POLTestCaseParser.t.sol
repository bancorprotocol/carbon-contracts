// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ICarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

contract POLTestCaseParser is Test {
    using stdJson for string;

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
        ICarbonPOL.Price initialPrice;
        PriceAtTimestamp[] pricesAtTimestamp;
    }

    /**
     * @dev helper function to get test cases by parsing test data json
     */
    function getTestCases() public returns (TestCase[] memory testCases) {
        string memory path = "./test/helpers/data/polPricingTestData.json";
        string memory json = vm.readFile(path);
        testCases = parseTestCases(json, "testCase");

        return testCases;
    }

    /**
     * @dev helper function to parse test data source and target amounts
     */
    function parseInitialPrice(
        string memory json,
        string memory initialParseString
    ) private returns (ICarbonPOL.Price memory price) {
        uint256 initialPriceSourceAmount = vm.parseJsonUint(
            json,
            string.concat(initialParseString, "].initialPriceSourceAmount")
        );
        uint256 initialPriceTargetAmount = vm.parseJsonUint(
            json,
            string.concat(initialParseString, "].initialPriceTargetAmount")
        );
        price = ICarbonPOL.Price({
            sourceAmount: uint128(initialPriceSourceAmount),
            targetAmount: uint128(initialPriceTargetAmount)
        });
    }

    /**
     * @dev helper function to parse test data json object to TestCase[] struct
     */
    function parseTestCases(
        string memory json,
        string memory templateName
    ) private returns (TestCase[] memory testCases) {
        string memory initialParseString = string.concat("$.", templateName);

        // read the test case length
        string[] memory testCaseString = vm.parseJsonStringArray(json, initialParseString);
        uint256 testCaseLength = testCaseString.length;

        initialParseString = string.concat(initialParseString, "[");

        // initialize test cases array
        testCases = new TestCase[](testCaseLength);

        for (uint256 i = 0; i < testCaseLength; ++i) {
            // get the correct testCase index to parse
            string memory parseString = string.concat(initialParseString, Strings.toString(i));

            // Decode the initial price
            testCases[i].initialPrice = parseInitialPrice(json, parseString);

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

            testCases[i].pricesAtTimestamp = pricesAtTimestamp;
        }
        return testCases;
    }

    /// @dev convert a price at timestamp struct to uint256
    function convertPriceAtTimestampToUint(
        PriceAtTimestampString memory priceAtTimestampString
    ) private pure returns (PriceAtTimestamp memory priceAtTimestamp) {
        return
            PriceAtTimestamp({
                timestamp: uint32(stringToUint(priceAtTimestampString.timestamp)),
                sourceAmount: uint128(stringToUint(priceAtTimestampString.sourceAmount)),
                targetAmount: uint128(stringToUint(priceAtTimestampString.targetAmount))
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
