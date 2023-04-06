// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Token } from "../token/Token.sol";
import { MAX_GAP } from "../utility/Constants.sol";

struct Pair {
    uint128 id;
    Token[2] tokens;
}

abstract contract Pairs is Initializable {
    error PairAlreadyExists();
    error PairDoesNotExist();

    // unique incremental id representing a pair
    uint128 private _lastPairId;

    // mapping of pairs of tokens to their pair id, tokens are sorted at any order
    mapping(Token => mapping(Token => uint128)) private _pairIds;

    // mapping between a pairId to its Pair object
    mapping(uint128 => Token[2]) private _pairsStorage;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 3] private __gap;

    /**
     * @dev triggered when a new pair is created
     */
    event PairCreated(uint128 indexed pairId, Token indexed token0, Token indexed token1);

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __Pairs_init() internal onlyInitializing {
        __Pairs_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __Pairs_init_unchained() internal onlyInitializing {}

    // solhint-enable func-name-mixedcase

    /**
     * @dev generates and stores a new pair, tokens are assumed unique and valid
     */
    function _createPair(Token token0, Token token1) internal returns (Pair memory) {
        // validate pair existence
        if (_pairExists(token0, token1)) {
            revert PairAlreadyExists();
        }

        // sort tokens
        Token[2] memory sortedTokens = _sortTokens(token0, token1);

        // increment pair id
        uint128 id = _lastPairId + 1;
        _lastPairId = id;

        // store pair
        _pairsStorage[id] = sortedTokens;
        _pairIds[sortedTokens[0]][sortedTokens[1]] = id;

        emit PairCreated(id, sortedTokens[0], sortedTokens[1]);
        return Pair({ id: id, tokens: sortedTokens });
    }

    /**
     * @dev return a pair matching the given tokens
     */
    function _pair(Token token0, Token token1) internal view returns (Pair memory) {
        // sort tokens
        Token[2] memory sortedTokens = _sortTokens(token0, token1);

        // validate pair existence
        if (!_pairExists(token0, token1)) {
            revert PairDoesNotExist();
        }

        // return pair
        uint128 id = _pairIds[sortedTokens[0]][sortedTokens[1]];
        return Pair({ id: id, tokens: sortedTokens });
    }

    function _pairById(uint128 pairId) internal view returns (Pair memory) {
        Token[2] memory tokens = _pairsStorage[pairId];
        if (Token.unwrap(tokens[0]) == address(0)) {
            revert PairDoesNotExist();
        }
        return Pair({ id: pairId, tokens: tokens });
    }

    /**
     * @dev check for the existence of a pair (pair id's are sequential integers starting at 1)
     */
    function _pairExists(Token token0, Token token1) internal view returns (bool) {
        // sort tokens
        Token[2] memory sortedTokens = _sortTokens(token0, token1);

        if (_pairIds[sortedTokens[0]][sortedTokens[1]] == 0) {
            return false;
        }
        return true;
    }

    /**
     * @dev returns a list of all supported pairs
     */
    function _pairs() internal view returns (Token[2][] memory) {
        uint128 length = _lastPairId;
        Token[2][] memory list = new Token[2][](length);
        for (uint128 i = 0; i < length; i++) {
            list[i] = _pairsStorage[i + 1];
        }

        return list;
    }

    /**
     * returns the given tokens sorted by address value, smaller first
     */
    function _sortTokens(Token token0, Token token1) private pure returns (Token[2] memory) {
        return Token.unwrap(token0) < Token.unwrap(token1) ? [token0, token1] : [token1, token0];
    }
}
