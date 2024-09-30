// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./TradingStorageUtils.sol";

/**
 * @dev External library for array getters to save bytecode size in facet libraries
 */

library ArrayGetters {
    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollaterals() public view returns (ITradingStorage.Collateral[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        uint256 collateralsCount = s.lastCollateralIndex + 1;
        ITradingStorage.Collateral[] memory collaterals = new ITradingStorage.Collateral[](
            collateralsCount
        );

        for (uint8 i; i < collateralsCount; ++i) {
            collaterals[i] = s.collaterals[i];
        }

        return collaterals;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTraders(uint32 _offset, uint32 _limit) public view returns (address[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        if (s.traders.length == 0) return new address[](0);

        uint256 lastIndex = s.traders.length - 1;
        _limit = _limit == 0 || _limit > lastIndex ? uint32(lastIndex) : _limit;

        address[] memory traders = new address[](_limit - _offset + 1);

        uint32 currentIndex;
        for (uint32 i = _offset; i <= _limit; ++i) {
            address trader = s.traders[i];
            if (s.userCounters[trader].openCount > 0) {
                traders[currentIndex++] = trader;
            }
        }

        return traders;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTrades(address _trader) public view returns (ITradingStorage.Trade[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader];
        ITradingStorage.Trade[] memory trades = new ITradingStorage.Trade[](
            traderCounter.openCount
        );

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            ITradingStorage.Trade memory trade = s.trades[_trader][i];
            if (trade.isOpen) {
                trades[currentIndex++] = trade;
            }
        }

        return trades;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTrades(
        uint256 _offset,
        uint256 _limit
    ) external view returns (ITradingStorage.Trade[] memory) {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);

        uint256 currentTradeIndex; // current global trade index
        uint256 currentArrayIndex; // current index in returned trades array

        ITradingStorage.Trade[] memory trades = new ITradingStorage.Trade[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < traders.length; ++i) {
            ITradingStorage.Trade[] memory traderTrades = getTrades(traders[i]);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderTrades.length; ++j) {
                if (currentTradeIndex >= _offset && currentTradeIndex <= _limit) {
                    trades[currentArrayIndex++] = traderTrades[j];
                }
                currentTradeIndex++;
            }
        }

        return trades;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradeInfos(
        address _trader
    ) public view returns (ITradingStorage.TradeInfo[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader];
        ITradingStorage.TradeInfo[] memory tradeInfos = new ITradingStorage.TradeInfo[](
            traderCounter.openCount
        );

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.trades[_trader][i].isOpen) {
                tradeInfos[currentIndex++] = s.tradeInfos[_trader][i];
            }
        }

        return tradeInfos;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradeInfos(
        uint256 _offset,
        uint256 _limit
    ) external view returns (ITradingStorage.TradeInfo[] memory) {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);

        uint256 currentTradeIndex; // current global trade index
        uint256 currentArrayIndex; // current index in returned trades array

        ITradingStorage.TradeInfo[] memory tradesInfos = new ITradingStorage.TradeInfo[](
            _limit - _offset + 1
        );

        // Fetch all trades for each trader
        for (uint256 i; i < traders.length; ++i) {
            ITradingStorage.TradeInfo[] memory traderTradesInfos = getTradeInfos(traders[i]);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderTradesInfos.length; ++j) {
                if (currentTradeIndex >= _offset && currentTradeIndex <= _limit) {
                    tradesInfos[currentArrayIndex++] = traderTradesInfos[j];
                }
                currentTradeIndex++;
            }
        }

        return tradesInfos;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradesLiquidationParams(
        address _trader
    ) public view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader];
        IPairsStorage.GroupLiquidationParams[]
            memory tradeLiquidationParams = new IPairsStorage.GroupLiquidationParams[](
                traderCounter.openCount
            );

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.trades[_trader][i].isOpen) {
                tradeLiquidationParams[currentIndex++] = s.tradeLiquidationParams[_trader][i];
            }
        }

        return tradeLiquidationParams;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradesLiquidationParams(
        uint256 _offset,
        uint256 _limit
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);

        uint256 currentTradeLiquidationParamIndex; // current global trade liquidation params index
        uint256 currentArrayIndex; // current index in returned trade liquidation params array

        IPairsStorage.GroupLiquidationParams[]
            memory tradeLiquidationParams = new IPairsStorage.GroupLiquidationParams[](
                _limit - _offset + 1
            );

        // Fetch all trades for each trader
        for (uint256 i; i < traders.length; ++i) {
            IPairsStorage.GroupLiquidationParams[]
                memory traderLiquidationParams = getTradesLiquidationParams(traders[i]);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderLiquidationParams.length; ++j) {
                if (
                    currentTradeLiquidationParamIndex >= _offset &&
                    currentTradeLiquidationParamIndex <= _limit
                ) {
                    tradeLiquidationParams[currentArrayIndex++] = traderLiquidationParams[j];
                }
                currentTradeLiquidationParamIndex++;
            }
        }

        return tradeLiquidationParams;
    }
}
