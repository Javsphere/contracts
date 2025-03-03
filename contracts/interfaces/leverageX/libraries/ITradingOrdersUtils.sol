// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/ITradingStorage.sol";
import "../types/ITradingOrders.sol";

/**
 * @custom:version 8
 * @dev Interface for JavTradingStorage facet (inherits types and also contains functions, events, and custom errors)
 */
interface ITradingOrdersUtils is ITradingOrders {
    /**
     * @dev Stores a new pending order
     * @param _pendingOrder the pending order to be stored
     */
    function storePendingOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external returns (ITradingStorage.PendingOrder memory);

    /**
     * @dev Closes a pending order
     * @param _orderId the id of the pending order to be closed
     */
    function closePendingOrder(ITradingStorage.Id memory _orderId) external;

    /**
     * @dev Returns a pending ordeer
     * @param _orderId id of the pending order
     */
    function getPendingOrder(
        ITradingStorage.Id memory _orderId
    ) external view returns (ITradingStorage.PendingOrder memory);

    /**
     * @dev Returns all pending orders for a trader
     * @param _user address of the trader
     */
    function getPendingOrders(
        address _user
    ) external view returns (ITradingStorage.PendingOrder[] memory);

    /**
     * @dev Returns all pending orders using a pagination system
     * @param _traders list of traders to return pendingOrder for
     * @param _offset index of first pendingOrder to return
     * @param _limit index of last pendingOrder to return
     */
    function getAllPendingOrdersForTraders(
        address[] memory _traders,
        uint256 _offset,
        uint256 _limit
    ) external view returns (ITradingStorage.PendingOrder[] memory);

    /**
     * @dev Returns all pending orders using a pagination system
     * @dev Calls `getAllPendingOrdersForTraders` internally with all traders.
     * @param _offset index of first pendingOrder to return
     * @param _limit index of last pendingOrder to return
     */
    function getAllPendingOrders(
        uint256 _offset,
        uint256 _limit
    ) external view returns (ITradingStorage.PendingOrder[] memory);

    /**
     * @dev Emitted when a new pending order is stored
     * @param pendingOrder the pending order stored
     */
    event PendingOrderStored(ITradingStorage.PendingOrder pendingOrder);

    /**
     * @dev Emitted when a pending order is closed
     * @param orderId the id of the pending order closed
     */
    event PendingOrderClosed(ITradingStorage.Id orderId);
}
