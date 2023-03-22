// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Utils } from "../utility/Utils.sol";
import { IVoucher } from "./interfaces/IVoucher.sol";
import { CarbonController } from "../carbon/CarbonController.sol";

contract Voucher is IVoucher, ERC721Enumerable, Utils, Ownable {
    using Strings for uint256;

    error CarbonControllerNotSet();

    // the carbon controller contract
    CarbonController private _carbonController;

    // a flag used to toggle between a unique URI per token / one global URI for all tokens
    bool private _useGlobalURI;

    // the prefix of a dynamic URI representing a single token
    string private __baseURI;

    // the suffix of a dynamic URI for e.g. `.json`
    string private _baseExtension;

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
     * @dev triggered when updating the address of the carbonController contract
     */
    event CarbonControllerUpdated(CarbonController carbonController);

    constructor(
        bool newUseGlobalURI,
        string memory newBaseURI,
        string memory newBaseExtension
    ) ERC721("Carbon Automated Trading Strategy", "CARBON-STRAT") {
        useGlobalURI(newUseGlobalURI);
        setBaseURI(newBaseURI);
        setBaseExtension(newBaseExtension);
    }

    /**
     * @inheritdoc IVoucher
     */
    function mint(address provider, uint256 strategyId) external only(address(_carbonController)) {
        _safeMint(provider, strategyId);
    }

    /**
     * @inheritdoc IVoucher
     */
    function burn(uint256 strategyId) external only(address(_carbonController)) {
        _burn(strategyId);
    }

    /**
     * @dev stores the carbonController address
     *
     * requirements:
     *
     * - the caller must be the owner of this contract
     */
    function setCarbonController(
        CarbonController carbonController
    ) external onlyOwner validAddress(address(carbonController)) {
        if (_carbonController == carbonController) {
            return;
        }

        _carbonController = carbonController;
        emit CarbonControllerUpdated(carbonController);
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

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), _baseExtension)) : "";
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
}
