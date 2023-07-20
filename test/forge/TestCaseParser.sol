// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Order, TradeAction } from "../../contracts/carbon/Strategies.sol";

contract TestCaseParser is Test {
    using stdJson for string;

    // solhint-disable var-name-mixedcase
    struct OrderString {
        string A;
        string B;
        string y;
        string z;
    }
    // solhint-enable var-name-mixedcase

    struct TestStrategy {
        Order[2] orders; // original strategy orders
        Order[2] expectedOrders; // expected orders after trading
    }

    struct TradeActionIntermediate {
        string amount;
        bytes strategyId;
    }

    struct TestCase {
        string sourceSymbol;
        string targetSymbol;
        TestStrategy[] strategies;
        TradeAction[] tradeActions;
        bool byTargetAmount;
        uint256 sourceAmount;
        uint256 targetAmount;
    }

    /**
     * @dev helper function to get a test case data struct by parsing test data json
     */
    function getTestCase(
        string memory sourceSymbol,
        string memory targetSymbol,
        bool byTargetAmount
    ) public returns (TestCase memory testCase) {
        TestStrategy[] memory strategies;
        TradeAction[] memory tradeActions;
        uint256 sourceAmount;
        uint256 targetAmount;
        if (byTargetAmount) {
            (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                "testCaseTemplateByTargetAmount"
            );
        } else {
            (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                "testCaseTemplateBySourceAmount"
            );
        }

        return
            TestCase({
                sourceSymbol: sourceSymbol,
                targetSymbol: targetSymbol,
                strategies: strategies,
                tradeActions: tradeActions,
                byTargetAmount: byTargetAmount,
                sourceAmount: sourceAmount,
                targetAmount: targetAmount
            });
    }

    /**
     * @dev helper function to get a test case data struct by parsing test data json
     */
    function getTestCase(
        string memory sourceSymbol,
        string memory targetSymbol,
        bool byTargetAmount,
        bool inverseOrders
    ) public returns (TestCase memory testCase) {
        TestStrategy[] memory strategies;
        TradeAction[] memory tradeActions;
        uint256 sourceAmount;
        uint256 targetAmount;
        if (byTargetAmount) {
            (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                "testCaseTemplateByTargetAmount"
            );
        } else {
            (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                "testCaseTemplateBySourceAmount"
            );
        }

        if (inverseOrders) {
            // swap orders for some strategies if true
            for (uint256 i = 0; i < strategies.length; i += 2) {
                Order memory tempOrder = strategies[i].orders[0];
                Order memory tempOrderExpected = strategies[i].expectedOrders[0];

                strategies[i].orders[0] = strategies[i].orders[1];
                strategies[i].expectedOrders[0] = strategies[i].expectedOrders[1];
                strategies[i].orders[1] = tempOrder;
                strategies[i].expectedOrders[1] = tempOrderExpected;
            }
        }

        return
            TestCase({
                sourceSymbol: sourceSymbol,
                targetSymbol: targetSymbol,
                strategies: strategies,
                tradeActions: tradeActions,
                byTargetAmount: byTargetAmount,
                sourceAmount: sourceAmount,
                targetAmount: targetAmount
            });
    }

    /**
     * @dev helper function to get a test case data struct by parsing test data json (overriden with additional args)
     */
    function getTestCase(
        string memory sourceSymbol,
        string memory targetSymbol,
        bool byTargetAmount,
        bool equalHighestAndMarginalRate,
        bool inverseOrders
    ) public returns (TestCase memory testCase) {
        TestStrategy[] memory strategies;
        TradeAction[] memory tradeActions;
        uint256 sourceAmount;
        uint256 targetAmount;
        if (equalHighestAndMarginalRate) {
            if (byTargetAmount) {
                (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                    "testCaseTemplateByTargetAmountEqualHighestAndMarginalRate"
                );
            } else {
                (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                    "testCaseTemplateBySourceAmountEqualHighestAndMarginalRate"
                );
            }
        } else {
            if (byTargetAmount) {
                (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                    "testCaseTemplateByTargetAmount"
                );
            } else {
                (strategies, tradeActions, sourceAmount, targetAmount) = parseTestDataTemplate(
                    "testCaseTemplateBySourceAmount"
                );
            }
        }
        if (inverseOrders) {
            // swap orders for some strategies if true
            for (uint256 i = 0; i < strategies.length; i += 2) {
                Order memory tempOrder = strategies[i].orders[0];
                Order memory tempOrderExpected = strategies[i].expectedOrders[0];

                strategies[i].orders[0] = strategies[i].orders[1];
                strategies[i].expectedOrders[0] = strategies[i].expectedOrders[1];
                strategies[i].orders[1] = tempOrder;
                strategies[i].expectedOrders[1] = tempOrderExpected;
            }
        }

        return
            TestCase({
                sourceSymbol: sourceSymbol,
                targetSymbol: targetSymbol,
                strategies: strategies,
                tradeActions: tradeActions,
                byTargetAmount: byTargetAmount,
                sourceAmount: sourceAmount,
                targetAmount: targetAmount
            });
    }

    /**
     * @dev helper function to parse test data json object to TestStrategy[], TradeAction[] structs, source and target amounts
     */
    function parseTestDataTemplate(
        string memory templateName
    )
        public
        returns (
            TestStrategy[] memory strategies,
            TradeAction[] memory tradeActions,
            uint256 sourceAmount,
            uint256 targetAmount
        )
    {
        string memory json = vm.readFile("./test/carbon/trading/testDataFormatted.json");

        strategies = parseStrategies(json, templateName);
        tradeActions = parseTradeActions(json, templateName);
        (sourceAmount, targetAmount) = parseSourceAndTargetAmounts(json, templateName);
    }

    /**
     * @dev helper function to parse test data source and target amounts
     */
    function parseSourceAndTargetAmounts(
        string memory json,
        string memory templateName
    ) private returns (uint256 sourceAmount, uint256 targetAmount) {
        string memory initialParseString = string.concat("$.", templateName);
        sourceAmount = vm.parseJsonUint(json, string.concat(initialParseString, ".sourceAmount"));
        targetAmount = vm.parseJsonUint(json, string.concat(initialParseString, ".targetAmount"));
    }

    /**
     * @dev helper function to parse test data json object to TestStrategy[] struct
     */
    function parseStrategies(
        string memory json,
        string memory templateName
    ) private returns (TestStrategy[] memory strategies) {
        string memory initialParseString = string.concat("$.", templateName);
        initialParseString = string.concat(initialParseString, ".strategies");

        // read the strategies length
        string[] memory strategiesString = vm.parseJsonStringArray(json, initialParseString);
        uint256 strategiesLength = strategiesString.length;

        initialParseString = string.concat(initialParseString, "[");

        // initialize strategies array
        strategies = new TestStrategy[](strategiesLength);

        for (uint i = 0; i < strategiesLength; ++i) {
            // get the correct strategy index to parse
            string memory parseString = string.concat(initialParseString, Strings.toString(i));

            // Parse the orders field into a bytes array
            bytes memory order0Bytes = json.parseRaw(string.concat(parseString, "].orders[0]"));
            bytes memory order1Bytes = json.parseRaw(string.concat(parseString, "].orders[1]"));
            bytes memory expectedOrder0Bytes = json.parseRaw(string.concat(parseString, "].expectedOrders[0]"));
            bytes memory expectedOrder1Bytes = json.parseRaw(string.concat(parseString, "].expectedOrders[1]"));

            // Decode the bytes array into an Order struct
            Order memory order0 = convertOrderStructToUint(abi.decode(order0Bytes, (OrderString)));
            Order memory order1 = convertOrderStructToUint(abi.decode(order1Bytes, (OrderString)));
            Order memory expectedOrder0 = convertOrderStructToUint(abi.decode(expectedOrder0Bytes, (OrderString)));
            Order memory expectedOrder1 = convertOrderStructToUint(abi.decode(expectedOrder1Bytes, (OrderString)));
            strategies[i].orders = [order0, order1];
            strategies[i].expectedOrders = [expectedOrder0, expectedOrder1];
        }
        return strategies;
    }

    /**
     * @dev helper function to parse test data json object to TradeAction[] struct
     */
    function parseTradeActions(
        string memory json,
        string memory templateName
    ) private returns (TradeAction[] memory tradeActions) {
        string memory initialParseString = string.concat("$.", templateName);
        initialParseString = string.concat(initialParseString, ".tradeActions");

        // read the trade actions length
        string[] memory tradeActionsString = vm.parseJsonStringArray(json, initialParseString);
        uint256 tradeActionsLength = tradeActionsString.length;

        initialParseString = string.concat(initialParseString, "[");

        // initialize trade actions array
        tradeActions = new TradeAction[](tradeActionsLength);

        for (uint i = 0; i < tradeActionsLength; ++i) {
            // get the correct trade action index to parse
            string memory parseString = string.concat(initialParseString, Strings.toString(i));

            // Parse the trade actions field into bytes format
            bytes memory tradeActionBytes = json.parseRaw(string.concat(parseString, "]"));
            // Decode the bytes into an TradeActionIntermediate struct
            TradeActionIntermediate memory tradeActionIntermediate = abi.decode(
                tradeActionBytes,
                (TradeActionIntermediate)
            );
            // Format the TradeAction struct properly
            tradeActions[i] = TradeAction({
                strategyId: bytesToUint(tradeActionIntermediate.strategyId),
                amount: uint128(stringToUint((tradeActionIntermediate.amount)))
            });
        }
        return tradeActions;
    }

    /// @dev convert an order struct to uint
    function convertOrderStructToUint(OrderString memory orderString) private pure returns (Order memory order) {
        return
            Order({
                y: uint128(stringToUint(orderString.y)),
                z: uint128(stringToUint(orderString.z)),
                A: uint64(stringToUint(orderString.A)),
                B: uint64(stringToUint(orderString.B))
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
