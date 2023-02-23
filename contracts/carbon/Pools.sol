// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Token } from "../token/Token.sol";
import { MAX_GAP } from "../utility/Constants.sol";

import { CountersUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

struct Pool {
    uint256 id;
    Token token0;
    Token token1;
}

abstract contract Pools is Initializable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    error PoolAlreadyExist();
    error PoolDoesNotExist();

    // unique incremental id representing a pool
    CountersUpgradeable.Counter private _lastPoolId;

    // mapping of pairs of tokens to their pool id, tokens are sorted at any order
    mapping(Token => mapping(Token => uint256)) private _poolIds;

    // mapping between a poolId to its Pool object
    mapping(uint256 => Pool) private _poolsStorage;

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
        if (_poolExists(token0, token1)) {
            revert PoolAlreadyExist();
        }

        // sort tokens by address value, smaller first
        (Token _token0, Token _token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        // increment pool id
        _lastPoolId.increment();
        uint256 id = _lastPoolId.current();

        // store pool
        Pool memory newPool = Pool({ id: id, token0: _token0, token1: _token1 });
        _poolsStorage[id] = newPool;
        _poolIds[token0][token1] = newPool.id;
        _poolIds[token1][token0] = newPool.id; // optimization, store reversed order

        emit PoolCreated(newPool.id, newPool.token0, newPool.token1);
        return newPool;
    }

    /**
     * @dev return a pool matching the given tokens
     */
    function _pool(Token token0, Token token1) internal view returns (Pool memory) {
        _validatePoolExistance(token0, token1);
        uint256 id = _poolIds[token0][token1];
        return _poolsStorage[id];
    }

    /**
     * @dev check for the existance of a pool (pool id's are sequential intergers starting at 1)
     */
    function _poolExists(Token token0, Token token1) internal view returns (bool) {
        if (_poolIds[token0][token1] == 0) {
            return false;
        }
        return true;
    }

    /**
     * @dev check for the existance of a pool or revert
     */
    function _validatePoolExistance(Token token0, Token token1) private view {
        if (!_poolExists(token0, token1)) {
            revert PoolDoesNotExist();
        }
    }

    /**
     * @dev returns a list of all supported pairs
     */
    function _pairs() internal view returns (address[2][] memory) {
        uint256 length = _lastPoolId.current();
        address[2][] memory list = new address[2][](length);
        for (uint256 i = 0; i < length; i++) {
            Pool memory pool = _poolsStorage[i + 1];
            list[i] = [address(pool.token0), address(pool.token1)];
        }

        return list;
    }
}
