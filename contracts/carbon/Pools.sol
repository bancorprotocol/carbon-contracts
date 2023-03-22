// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Token } from "../token/Token.sol";
import { MAX_GAP } from "../utility/Constants.sol";

import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

struct Pool {
    uint256 id;
    Token[2] tokens;
}

abstract contract Pools is Initializable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct StoredPool {
        Token[2] tokens;
    }

    error PoolAlreadyExists();
    error PoolDoesNotExist();

    // unique incremental id representing a pool
    CountersUpgradeable.Counter private _lastPoolId;

    // mapping of pairs of tokens to their pool id, tokens are sorted at any order
    mapping(Token => mapping(Token => uint256)) private _poolIds;

    // mapping between a poolId to its Pool object
    mapping(uint256 => StoredPool) private _poolsStorage;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 3] private __gap;

    /**
     * @dev triggered when a new pool is created
     */
    event PoolCreated(uint256 indexed poolId, Token indexed token0, Token indexed token1);

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __Pools_init() internal onlyInitializing {
        __Pools_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __Pools_init_unchained() internal onlyInitializing {}

    // solhint-enable func-name-mixedcase

    /**
     * @dev generates and stores a new pool, tokens are assumed unique and valid
     */
    function _createPool(Token token0, Token token1) internal returns (Pool memory) {
        // validate pool existence
        if (_poolExists(token0, token1)) {
            revert PoolAlreadyExists();
        }

        // sort tokens
        Token[2] memory sortedTokens = _sortTokens(token0, token1);

        // increment pool id
        _lastPoolId.increment();
        uint256 id = _lastPoolId.current();

        // store pool
        StoredPool memory newPool = StoredPool({ tokens: sortedTokens });
        _poolsStorage[id] = newPool;
        _poolIds[sortedTokens[0]][sortedTokens[1]] = id;

        emit PoolCreated(id, newPool.tokens[0], newPool.tokens[1]);
        return Pool({ id: id, tokens: sortedTokens });
    }

    /**
     * @dev return a pool matching the given tokens
     */
    function _pool(Token token0, Token token1) internal view returns (Pool memory) {
        // sort tokens
        Token[2] memory sortedTokens = _sortTokens(token0, token1);

        // validate pool existence
        if (!_poolExists(token0, token1)) {
            revert PoolDoesNotExist();
        }

        // return pool
        uint256 id = _poolIds[sortedTokens[0]][sortedTokens[1]];
        return Pool({ id: id, tokens: sortedTokens });
    }

    function _poolById(uint256 poolId) internal view returns (Pool memory) {
        StoredPool memory storedPool = _poolsStorage[poolId];
        if (address(storedPool.tokens[0]) == address(0)) {
            revert PoolDoesNotExist();
        }
        return Pool({ id: poolId, tokens: storedPool.tokens });
    }

    /**
     * @dev check for the existence of a pool (pool id's are sequential integers starting at 1)
     */
    function _poolExists(Token token0, Token token1) internal view returns (bool) {
        // sort tokens
        Token[2] memory sortedTokens = _sortTokens(token0, token1);

        if (_poolIds[sortedTokens[0]][sortedTokens[1]] == 0) {
            return false;
        }
        return true;
    }

    /**
     * @dev returns a list of all supported pairs
     */
    function _pairs() internal view returns (Token[2][] memory) {
        uint256 length = _lastPoolId.current();
        Token[2][] memory list = new Token[2][](length);
        for (uint256 i = 0; i < length; i++) {
            StoredPool memory pool = _poolsStorage[i + 1];
            list[i] = pool.tokens;
        }

        return list;
    }

    /**
     * returns the given tokens sorted by address value, smaller first
     */
    function _sortTokens(Token token0, Token token1) private pure returns (Token[2] memory) {
        return token0 < token1 ? [token0, token1] : [token1, token0];
    }
}
