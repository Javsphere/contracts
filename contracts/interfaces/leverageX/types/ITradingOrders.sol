// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;


import "./ITradingStorage.sol";

/**
 * @custom:version 8
 * @dev Contains the types for the JavTradingStorage facet
 */
interface ITradingOrders {
    struct TradingOrders {
        mapping(address => mapping(uint32 => ITradingStorage.PendingOrder)) pendingOrders;
        mapping(address => ITradingStorage.Counter) pendingOrdersCounters;
        uint256[48] __gap;
    }
}