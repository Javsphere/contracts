// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @custom:version 8
 * @dev Chain helpers internal library
 */
library ChainUtils {
    uint256 internal constant BASE_MAINNET = 8453;
    uint256 internal constant TESTNET = 84532;
    // Supported chains

    error Overflow();
    error UnsupportedChain();

    /**
     * @dev Returns blockNumber converted to uint48
     * @param blockNumber block number to convert
     */
    function getUint48BlockNumber(uint256 blockNumber) internal pure returns (uint48) {
        if (blockNumber > type(uint48).max) revert Overflow();
        return uint48(blockNumber);
    }

    /**
     * @dev Converts blocks to seconds for the current chain.
     * @dev Important: the result is an estimation and may not be accurate. Use with caution.
     * @param _blocks block count to convert to seconds
     */
    function convertBlocksToSeconds(uint256 _blocks) internal view returns (uint256) {
        uint256 millisecondsPerBlock;

        if (block.chainid == BASE_MAINNET) {
            millisecondsPerBlock = 2000; // 2 seconds per block
        } else if (block.chainid == TESTNET) {
            millisecondsPerBlock = 2000; // 2 second per block
        } else {
            revert UnsupportedChain();
        }

        return Math.mulDiv(_blocks, millisecondsPerBlock, 1000, Math.Rounding.Ceil);
    }
}
