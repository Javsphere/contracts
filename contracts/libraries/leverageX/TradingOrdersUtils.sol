// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/leverageX/IJavMultiCollatDiamond.sol";

import "./StorageUtils.sol";
import "./AddressStoreUtils.sol";
import "../../interfaces/leverageX/types/ITradingOrders.sol";

/**
 * @custom:version 8
 * @dev JavTradingStorage facet internal library
 */

library TradingOrdersUtils {
    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function storePendingOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal returns (ITradingStorage.PendingOrder memory) {
        if (_pendingOrder.user == address(0)) revert IGeneralErrors.ZeroAddress();

        ITradingOrders.TradingOrders storage s = _getStorage();

        _getMultiCollatDiamond().validateTrade(_pendingOrder.trade);

        if (_pendingOrder.maxSlippageP == 0) revert ITradingStorageUtils.MaxSlippageZero();

        uint32 blockNumber = uint32(block.number);
        ITradingStorage.Counter memory counter = s.pendingOrdersCounters[_pendingOrder.user];

        _pendingOrder.index = counter.currentIndex;
        _pendingOrder.isOpen = true;
        _pendingOrder.createdBlock = blockNumber;

        counter.currentIndex++;
        counter.openCount++;

        s.pendingOrders[_pendingOrder.user][_pendingOrder.index] = _pendingOrder;
        s.pendingOrdersCounters[_pendingOrder.user] = counter;

        if (!_getMultiCollatDiamond().getTraderStored(_pendingOrder.user)) {
            _getMultiCollatDiamond().storeTrader(_pendingOrder.user);
        }

        emit ITradingOrdersUtils.PendingOrderStored(_pendingOrder);

        return _pendingOrder;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function closePendingOrder(ITradingStorage.Id memory _orderId) internal {
        ITradingOrders.TradingOrders storage s = _getStorage();
        ITradingStorage.PendingOrder storage pendingOrder = s.pendingOrders[_orderId.user][
            _orderId.index
        ];

        if (!pendingOrder.isOpen) revert IGeneralErrors.DoesntExist();

        pendingOrder.isOpen = false;
        s.pendingOrdersCounters[_orderId.user].openCount--;

        emit ITradingOrdersUtils.PendingOrderClosed(_orderId);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getPendingOrder(
        ITradingStorage.Id memory _orderId
    ) internal view returns (ITradingStorage.PendingOrder memory) {
        return _getStorage().pendingOrders[_orderId.user][_orderId.index];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRADING_ORDERS_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (ITradingOrders.TradingOrders storage s) {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }
}
