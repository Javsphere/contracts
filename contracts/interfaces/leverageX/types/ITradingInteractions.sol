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
        uint256[46] __gap;
    }

}