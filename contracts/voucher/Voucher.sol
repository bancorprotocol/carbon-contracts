// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import { IERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC165Upgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Utils, InvalidIndices } from "../utility/Utils.sol";
import { MAX_GAP } from "../utility/Constants.sol";

import { IVoucher } from "./interfaces/IVoucher.sol";

contract Voucher is IVoucher, Upgradeable, ERC721Upgradeable, OwnableUpgradeable, Utils {
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    error ControllerNotSet();
    error BatchNotSupported();

    // the controller contract
    address private _controller;

    // a flag used to toggle between a unique URI per token / one global URI for all tokens
    bool private _useGlobalURI;

    // the prefix of a dynamic URI representing a single token
    string private __baseURI;

    // the suffix of a dynamic URI for e.g. `.json`
    string private _baseExtension;

    // a mapping between an owner to its tokenIds
    mapping(address => EnumerableSet.UintSet) internal _ownedTokens;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 4] private __gap;

    /**
     @dev triggered when updating useGlobalURI
     */
    event UseGlobalURIUpdated(bool newUseGlobalURI);

    /**
     * @dev triggered when updating the baseURI
     */
    event BaseURIUpdated(string newBaseURI);

    /**
     * @dev triggered when updating the baseExtension
     */
    event BaseExtensionUpdated(string newBaseExtension);

    /**
     * @dev triggered when updating the address of the controller contract
     */
    event ControllerUpdated(address indexed controller);

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize(
        bool newUseGlobalURI,
        string memory newBaseURI,
        string memory newBaseExtension
    ) external initializer {
        __Voucher_init(newUseGlobalURI, newBaseURI, newBaseExtension);
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __Voucher_init(
        bool newUseGlobalURI,
        string memory newBaseURI,
        string memory newBaseExtension
    ) internal onlyInitializing {
        __Upgradeable_init();
        __ERC721_init("Carbon Automated Trading Strategy", "CARBON-STRAT");
        __Ownable_init();

        __Voucher_init_unchained(newUseGlobalURI, newBaseURI, newBaseExtension);
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __Voucher_init_unchained(
        bool newUseGlobalURI,
        string memory newBaseURI,
        string memory newBaseExtension
    ) internal onlyInitializing {
        _useGlobalURI = newUseGlobalURI;
        __baseURI = newBaseURI;
        _baseExtension = newBaseExtension;
    }

    /**
     * @inheritdoc IERC165Upgradeable
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable, ERC721Upgradeable, IERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // solhint-enable func-name-mixedcase

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 1;
    }

    /**
     * @inheritdoc IVoucher
     */
    function mint(address owner, uint256 tokenId) external only(address(_controller)) {
        _safeMint(owner, tokenId);
    }

    /**
     * @inheritdoc IVoucher
     */
    function burn(uint256 tokenId) external only(address(_controller)) {
        _burn(tokenId);
    }

    /**
     * @inheritdoc IVoucher
     */
    function tokensByOwner(
        address owner,
        uint256 startIndex,
        uint256 endIndex
    ) external view validAddress(owner) returns (uint256[] memory) {
        EnumerableSet.UintSet storage tokenIds = _ownedTokens[owner];
        uint256 allLength = tokenIds.length();

        // when the endIndex is 0 or out of bound, set the endIndex to the last valid value
        if (endIndex == 0 || endIndex > allLength) {
            endIndex = allLength;
        }

        // revert when startIndex is out of bound
        if (startIndex > endIndex) {
            revert InvalidIndices();
        }

        // populate the result
        uint256 resultLength = endIndex - startIndex;
        uint256[] memory result = new uint256[](resultLength);
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = tokenIds.at(startIndex + i);
        }

        return result;
    }

    /**
     * @dev stores the controller address
     *
     * requirements:
     *
     * - the caller must be the owner of this contract
     */
    function setController(address controller) external onlyOwner validAddress(address(controller)) {
        if (_controller == controller) {
            return;
        }

        _controller = controller;
        emit ControllerUpdated(controller);
    }

    /**
     * @dev depending on the useGlobalURI flag, returns a unique URI point to a json representing the voucher,
     * or a URI of a global json used for all tokens
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        if (_useGlobalURI) {
            return baseURI;
        }

        if (bytes(baseURI).length > 0) {
            return string(abi.encodePacked(baseURI, tokenId.toString(), _baseExtension));
        }

        return "";
    }

    /**
     * @dev sets the base URI
     *
     * requirements:
     *
     * - the caller must be the owner of this contract
     */
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        __baseURI = newBaseURI;

        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev sets the base extension
     *
     * requirements:
     *
     * - the caller must be the owner of this contract
     */
    function setBaseExtension(string memory newBaseExtension) public onlyOwner {
        _baseExtension = newBaseExtension;

        emit BaseExtensionUpdated(newBaseExtension);
    }

    /**
     * @dev sets the useGlobalURI flag
     *
     * requirements:
     *
     * - the caller must be the owner of this contract
     */
    function useGlobalURI(bool newUseGlobalURI) public onlyOwner {
        if (_useGlobalURI == newUseGlobalURI) {
            return;
        }

        _useGlobalURI = newUseGlobalURI;
        emit UseGlobalURIUpdated(newUseGlobalURI);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI`, `tokenId`
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return __baseURI;
    }

    /**
     * @dev See {ERC721-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        if (batchSize > 1) {
            revert BatchNotSupported();
        }

        if (from == address(0)) {
            _ownedTokens[to].add(firstTokenId);
        } else if (from != to) {
            _ownedTokens[from].remove(firstTokenId);
        }
        if (to == address(0)) {
            _ownedTokens[from].remove(firstTokenId);
        } else if (to != from) {
            _ownedTokens[to].add(firstTokenId);
        }
    }
}
