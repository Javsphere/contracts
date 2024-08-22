// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/trade/types/ITradingStorage.sol";

/**
 *
 * @dev Internal library for important constants commonly used in many places
 */
library ConstantsUtils {
    uint256 internal constant P_10 = 1e10; // 10 decimals (DO NOT UPDATE)
    uint256 internal constant MAX_SL_P = 75; // -75% PNL
    uint256 internal constant MAX_PNL_P = 900; // 900% PnL (10x)
    uint256 internal constant LIQ_THRESHOLD_P = 90; // -90% pnl
    uint256 internal constant MAX_OPEN_NEGATIVE_PNL_P = 40 * 1e10; // -40% pnl

    function getMarketOrderTypes()
        internal
        pure
        returns (ITradingStorage.PendingOrderType[5] memory)
    {
        return [
            ITradingStorage.PendingOrderType.MARKET_OPEN,
            ITradingStorage.PendingOrderType.MARKET_CLOSE,
            ITradingStorage.PendingOrderType.UPDATE_LEVERAGE,
            ITradingStorage.PendingOrderType.MARKET_PARTIAL_OPEN,
            ITradingStorage.PendingOrderType.MARKET_PARTIAL_CLOSE
        ];
    }

    /**
     * @dev Returns pending order type (market open/limit open/stop open) for a trade type (trade/limit/stop)
     * @param _tradeType the trade type
     */
    function getPendingOpenOrderType(
        ITradingStorage.TradeType _tradeType
    ) internal pure returns (ITradingStorage.PendingOrderType) {
        return
            _tradeType == ITradingStorage.TradeType.TRADE
                ? ITradingStorage.PendingOrderType.MARKET_OPEN
                : _tradeType == ITradingStorage.TradeType.LIMIT
                ? ITradingStorage.PendingOrderType.LIMIT_OPEN
                : ITradingStorage.PendingOrderType.STOP_OPEN;
    }

    /**
     * @dev Returns true if order type is market
     * @param _orderType order type
     */
    function isOrderTypeMarket(
        ITradingStorage.PendingOrderType _orderType
    ) internal pure returns (bool) {
        ITradingStorage.PendingOrderType[5] memory marketOrderTypes = ConstantsUtils
            .getMarketOrderTypes();
        for (uint256 i; i < marketOrderTypes.length; ++i) {
            if (_orderType == marketOrderTypes[i]) return true;
        }
        return false;
    }
}
