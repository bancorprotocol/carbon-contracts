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
    function getTestCases() public view returns (TestCase[] memory testCases) {
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
    ) private pure returns (ICarbonPOL.Price memory price) {
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
    ) private pure returns (TestCase[] memory testCases) {
        string memory base = string.concat("$.", templateName);

        // read the test case count
        uint256 testCaseLength = vm.parseJsonUint(json, "$.testCaseCount");

        // initialize test cases array
        testCases = new TestCase[](testCaseLength);

        // base for indexed lookups
        string memory baseIdx = string.concat(base, "[");

        for (uint256 i = 0; i < testCaseLength; ++i) {
            // get the correct testCase index to parse
            string memory parseString = string.concat(baseIdx, Strings.toString(i));

            // Decode the initial price
            testCases[i].initialPrice = parseInitialPrice(json, parseString);

            // Decode the different prices at each timestamp
            uint256 tokenPriceLen = vm.parseJsonUint(json, string.concat(parseString, "].tokenPriceAtTimestampsCount"));

            // initialize token price at timestamp array
            PriceAtTimestamp[] memory pricesAtTimestamp = new PriceAtTimestamp[](tokenPriceLen);

            // fill in the token price at timestamp
            for (uint256 j = 0; j < tokenPriceLen; ++j) {
                // Parse the token price field into a bytes array
                string memory fullParseString = string.concat(parseString, "].tokenPriceAtTimestamps[");
                fullParseString = string.concat(fullParseString, Strings.toString(j));
                fullParseString = string.concat(fullParseString, "]");

                // Parse the element and decode into stringly struct, then convert to uint
                bytes memory tokenPriceAtTimestampBytes = json.parseRaw(fullParseString);
                pricesAtTimestamp[j] = convertPriceAtTimestampToUint(
                    abi.decode(tokenPriceAtTimestampBytes, (PriceAtTimestampString))
                );
            }

            testCases[i].pricesAtTimestamp = pricesAtTimestamp;
        }
        return testCases;
    }

    /// @dev convert a price at timestamp struct to uints
    function convertPriceAtTimestampToUint(
        PriceAtTimestampString memory s
    ) private pure returns (PriceAtTimestamp memory r) {
        return
            PriceAtTimestamp({
                timestamp: uint32(stringToUint(s.timestamp)),
                sourceAmount: uint128(stringToUint(s.sourceAmount)),
                targetAmount: uint128(stringToUint(s.targetAmount))
            });
    }

    /// @dev helper function to convert a string to uint256
    function stringToUint(string memory m) private pure returns (uint256 result) {
        bytes memory b = bytes(m);
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
