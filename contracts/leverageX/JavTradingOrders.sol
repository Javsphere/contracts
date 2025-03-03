// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./abstract/JavAddressStore.sol";
import "../libraries/leverageX/ArrayGetters.sol";
import "../interfaces/leverageX/libraries/ITradingOrdersUtils.sol";
import "../libraries/leverageX/TradingOrdersUtils.sol";

/**
 * @custom:version 8
 * @dev Facet #5: Trading orders
 */
contract JavTradingOrders is JavAddressStore, ITradingOrdersUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Interactions
    /// @inheritdoc ITradingOrdersUtils
    function storePendingOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf returns (ITradingStorage.PendingOrder memory) {
        return TradingOrdersUtils.storePendingOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingOrdersUtils
    function closePendingOrder(ITradingStorage.Id memory _orderId) external virtual onlySelf {
        TradingOrdersUtils.closePendingOrder(_orderId);
    }

    // Getters

    /// @inheritdoc ITradingOrdersUtils
    function getPendingOrder(
        ITradingStorage.Id memory _orderId
    ) external view returns (ITradingStorage.PendingOrder memory) {
        return TradingOrdersUtils.getPendingOrder(_orderId);
    }

    /// @inheritdoc ITradingOrdersUtils
    function getPendingOrders(
        address _user
    ) external view returns (ITradingStorage.PendingOrder[] memory) {
        return ArrayGetters.getPendingOrders(_user);
    }

    /// @inheritdoc ITradingOrdersUtils
    function getAllPendingOrdersForTraders(
        address[] memory _traders,
        uint256 _offset,
        uint256 _limit
    ) external view returns (ITradingStorage.PendingOrder[] memory) {
        return ArrayGetters.getAllPendingOrdersForTraders(_traders, _offset, _limit);
    }

    /// @inheritdoc ITradingOrdersUtils
    function getAllPendingOrders(
        uint256 _offset,
        uint256 _limit
    ) external view returns (ITradingStorage.PendingOrder[] memory) {
        return ArrayGetters.getAllPendingOrders(_offset, _limit);
    }
}
