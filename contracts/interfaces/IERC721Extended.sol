// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Extended is IERC721 {
    function safeMint(address to, string memory uri) external;

    function makeMigration(address to, uint256 _tokenId, string memory uri) external;

    function burn(uint256 value) external;
}
