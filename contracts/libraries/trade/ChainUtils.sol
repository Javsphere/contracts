// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @custom:version 8
 * @dev Chain helpers internal library
 */
library ChainUtils {
    // Supported chains

    error Overflow();

    /**
     * @dev Returns blockNumber converted to uint48
     * @param blockNumber block number to convert
     */
    function getUint48BlockNumber(uint256 blockNumber) internal pure returns (uint48) {
        if (blockNumber > type(uint48).max) revert Overflow();
        return uint48(blockNumber);
    }
}
