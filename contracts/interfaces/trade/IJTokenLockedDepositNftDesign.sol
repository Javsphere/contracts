// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./IJToken.sol";

/**
 * @custom:version 6.3
 * @dev Interface for GTokenLockedDepositNftDesign contract
 */
interface IJTokenLockedDepositNftDesign {
    function buildTokenURI(
        uint256 tokenId,
        IJToken.LockedDeposit memory lockedDeposit,
        string memory gTokenSymbol,
        string memory assetSymbol,
        uint8 numberInputDecimals,
        uint8 numberOutputDecimals
    ) external pure returns (string memory);
}
