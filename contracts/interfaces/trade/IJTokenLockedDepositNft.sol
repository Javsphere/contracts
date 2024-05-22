// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IJTokenLockedDepositNftDesign.sol";

/**
 * @custom:version 6.3
 * @dev Interface for GTokenLockedDepositNft contract
 */

interface IJTokenLockedDepositNft is IERC721 {
    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    event DesignUpdated(IJTokenLockedDepositNftDesign newValue);
    event DesignDecimalsUpdated(uint8 newValue);
}
