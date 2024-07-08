// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "./base/BaseUpgradable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";

contract InfinityPass is ERC721URIStorageUpgradeable, BaseUpgradable {
    uint256 public tokenIndex;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC721_init("Javsphere Infinity Pass", "JAVIP");
        tokenIndex = 1;
        __Base_init();
    }

    function safeMint(address to, string memory uri) external onlyOwner {
        _safeMint(to, tokenIndex);
        _setTokenURI(tokenIndex, uri);
        tokenIndex++;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        require(from == address(0), "InfinityPass: token transfer is BLOCKED");
        return super._update(to, tokenId, auth);
    }
}
