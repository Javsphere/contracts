// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @custom:version 8
 * @dev Contains the types for the JavTradingInteractions facet
 */
interface ITradingInteractions {



    struct TradingInteractionsStorage {
        uint80 __placeholder;
        address termsAndConditionsAddress;
        uint16 marketOrdersTimeoutBlocks; // 16 bits
        uint256[45] __gap;
    }

}