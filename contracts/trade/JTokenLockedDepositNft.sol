// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/IJTokenLockedDepositNft.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract JTOKENLockedDepositNft is ERC721Enumerable, IJTokenLockedDepositNft {
    address public jToken;
    address public owner;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        owner = msg.sender;
    }

    modifier onlyJTOKEN() {
        require(msg.sender == jToken, "ONLY_JTOKEN");
        _;
    }

    modifier onlyJTOKENManager() {
        require(msg.sender == IJToken(jToken).manager(), "ONLY_MANAGER");
        _;
    }

    function setJToken(address _jToken) external {
        require(msg.sender == owner, "ONLY_OWNER");
        jToken = _jToken;
    }

    function mint(address to, uint256 tokenId) external onlyJTOKEN {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyJTOKEN {
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {}
}
