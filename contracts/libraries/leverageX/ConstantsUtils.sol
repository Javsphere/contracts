// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/leverageX/types/ITradingStorage.sol";

/**
 *
 * @dev Internal library for important constants commonly used in many places
 */
library ConstantsUtils {
    uint256 internal constant P_10 = 1e10; // 10 decimals (DO NOT UPDATE)
    uint256 internal constant MAX_PNL_P = 900; // 900% PnL (10x)
    uint256 internal constant SL_LIQ_BUFFER_P = 10 * P_10; // SL has to be 10% closer than liq price
    uint256 internal constant LEGACY_LIQ_THRESHOLD_P = 90 * P_10; // -90% pnl
    uint256 internal constant MIN_LIQ_THRESHOLD_P = 50 * P_10; // -50% pnl
    uint256 internal constant MAX_OPEN_NEGATIVE_PNL_P = 40 * P_10; // -40% pnl
    uint256 internal constant MAX_LIQ_SPREAD_P = (5 * P_10) / 100; // 0.05%
    uint16 internal constant DEFAULT_MAX_CLOSING_SLIPPAGE_P = 1 * 1e3; // 1%

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
