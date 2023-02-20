// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Utils } from "../utility/Utils.sol";
import { IVoucher } from "./interfaces/IVoucher.sol";
import { CarbonController } from "../carbon/CarbonController.sol";

contract Voucher is IVoucher, ERC721Enumerable, Utils, Ownable {
    using Strings for uint256;

    // the carbon controller contract
    CarbonController private _carbonController;

    // a flag used to toggle between a unique URI per token / one global URI for all tokens
    bool private _useGlobalURI;

    // the prefix of a dynamic URI representing a single token
    string private __baseURI;

    // the suffix of a dynamic URI for e.g. `.json`
    string private _baseExtension;

    error CarbonControllerNotSet();

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
    function setCarbonController(CarbonController carbonController)
        external
        onlyOwner
        validAddress(address(carbonController))
    {
        _carbonController = carbonController;
    }

    /**
     * subscribes to the afterTokenTransfer hook where we update the strategy's owner following a transfer
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._afterTokenTransfer(from, to, tokenId, batchSize);

        if (address(_carbonController) == address(0)) {
            revert CarbonControllerNotSet();
        }

        if (from != address(0) && to != address(0)) {
            _carbonController.updateStrategyOwner(tokenId, to);
        }
    }

    /**
     * @dev depending on the useGlobalURI flag, returns a unique URI point to a json representing the voucher,
     * or a URI of a global json used for all tokens
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        if (_useGlobalURI == true) {
            return baseURI;
        } else {
            return
                bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), _baseExtension)) : "";
        }
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
    }

    /**
     * @dev sets the useGlobalURI flag
     *
     * requirements:
     *
     * - the caller must be the owner of this contract
     */
    function useGlobalURI(bool newUseGlobalURI) public onlyOwner {
        _useGlobalURI = newUseGlobalURI;
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI`, `tokenId`
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return __baseURI;
    }
}
