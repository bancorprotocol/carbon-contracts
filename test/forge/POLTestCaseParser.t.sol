// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ICarbonPOL } from "../../contracts/pol/CarbonPOL.sol";

contract POLTestCaseParser is Test {
    using stdJson for string;

    struct PriceAtTimestamp {
        uint32 timestamp;
        uint128 ethAmount;
        uint128 tokenAmount;
    }

    struct PriceAtTimestampString {
        string ethAmount;
        string timestamp;
        string tokenAmount;
    }

    struct TestCase {
        ICarbonPOL.Price initialPrice;
        PriceAtTimestamp[] pricesAtTimestamp;
    }

    /**
     * @dev helper function to get test cases by parsing test data json
     */
    function getTestCases() public returns (TestCase[] memory testCases) {
        string memory json = vm.readFile("./test/helpers/data/polPricingTestData.json");
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
        uint256 initialPriceEthAmount = vm.parseJsonUint(
            json,
            string.concat(initialParseString, "].initialPriceEthAmount")
        );
        uint256 initialPriceTokenAmount = vm.parseJsonUint(
            json,
            string.concat(initialParseString, "].initialPriceTokenAmount")
        );
        price = ICarbonPOL.Price({
            ethAmount: uint128(initialPriceEthAmount),
            tokenAmount: uint128(initialPriceTokenAmount)
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

        for (uint i = 0; i < testCaseLength; ++i) {
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
            for (uint j = 0; j < tokenPriceLen; ++j) {
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

    /// @dev convert a price at timestamp struct to uint
    function convertPriceAtTimestampToUint(
        PriceAtTimestampString memory priceAtTimestampString
    ) private pure returns (PriceAtTimestamp memory priceAtTimestamp) {
        return
            PriceAtTimestamp({
                timestamp: uint32(stringToUint(priceAtTimestampString.timestamp)),
                ethAmount: uint128(stringToUint(priceAtTimestampString.ethAmount)),
                tokenAmount: uint128(stringToUint(priceAtTimestampString.tokenAmount))
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
