// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ICarbonController } from "../carbon/interfaces/ICarbonController.sol";
import { Order, TradeAction } from "../carbon/Strategies.sol";
import { Token } from "../token/Token.sol";

/**
 * @dev token contract which attempts to re-enter CarbonController
 */
contract TestReentrantToken is ERC20 {
    ICarbonController private immutable _carbonController;

    enum ReenterFunctions {
        CREATE_PAIR,
        CREATE_STRATEGY,
        UPDATE_STRATEGY,
        DELETE_STRATEGY,
        TRADE_BY_SOURCE_AMOUNT,
        TRADE_BY_TARGET_AMOUNT,
        WITHDRAW_FEES
    }

    // which function to reenter using transferFrom
    ReenterFunctions private _reenterFunction;

    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        ICarbonController carbonControllerInit,
        ReenterFunctions reenterFunctionInit
    ) ERC20(name, symbol) {
        _carbonController = carbonControllerInit;
        _reenterFunction = reenterFunctionInit;
        _mint(msg.sender, totalSupply);
    }

    /// @dev Override ERC-20 transferFrom function to reenter carbonController
    function transferFrom(address from, address to, uint256 amount) public override(ERC20) returns (bool) {
        bool success = super.transferFrom(from, to, amount);

        // choose which carbonController function to reenter based on _reenterFunction
        if (_reenterFunction == ReenterFunctions.CREATE_PAIR) {
            _reenterCreatePair();
        } else if (_reenterFunction == ReenterFunctions.CREATE_STRATEGY) {
            _reenterCreateStrategy();
        } else if (_reenterFunction == ReenterFunctions.UPDATE_STRATEGY) {
            _reenterUpdateStrategy();
        } else if (_reenterFunction == ReenterFunctions.DELETE_STRATEGY) {
            _reenterDeleteStrategy();
        } else if (_reenterFunction == ReenterFunctions.TRADE_BY_SOURCE_AMOUNT) {
            _reenterTradeBySourceAmount();
        } else if (_reenterFunction == ReenterFunctions.TRADE_BY_TARGET_AMOUNT) {
            _reenterTradeByTargetAmount();
        } else if (_reenterFunction == ReenterFunctions.WITHDRAW_FEES) {
            _reenterWithdrawFees();
        }

        return success;
    }

    function _reenterCreatePair() private {
        // re-enter
        _carbonController.createPair(Token.wrap(address(1)), Token.wrap(address(2)));
    }

    function _reenterCreateStrategy() private {
        Order[2] memory orders = [_generateTestOrder(), _generateTestOrder()];
        // re-enter
        _carbonController.createStrategy(Token.wrap(address(1)), Token.wrap(address(2)), orders);
    }

    function _reenterUpdateStrategy() private {
        Order[2] memory orders = [_generateTestOrder(), _generateTestOrder()];
        // re-enter
        _carbonController.updateStrategy(0, orders, orders);
    }

    function _reenterDeleteStrategy() private {
        // re-enter
        _carbonController.deleteStrategy(0);
    }

    function _reenterTradeBySourceAmount() private {
        // re-enter
        TradeAction[] memory tradeActions = new TradeAction[](0);
        _carbonController.tradeBySourceAmount(
            Token.wrap(address(1)),
            Token.wrap(address(2)),
            tradeActions,
            block.timestamp,
            1
        );
    }

    function _reenterTradeByTargetAmount() private {
        // re-enter
        TradeAction[] memory tradeActions = new TradeAction[](0);
        _carbonController.tradeByTargetAmount(
            Token.wrap(address(1)),
            Token.wrap(address(2)),
            tradeActions,
            block.timestamp,
            type(uint128).max
        );
    }

    function _reenterWithdrawFees() private {
        // re-enter
        _carbonController.withdrawFees(Token.wrap(address(1)), type(uint256).max, address(this));
    }

    /// @dev helper function to generate test order
    function _generateTestOrder() private pure returns (Order memory order) {
        return Order({ y: 800000, z: 8000000, A: 736899889, B: 12148001999 });
    }
}
