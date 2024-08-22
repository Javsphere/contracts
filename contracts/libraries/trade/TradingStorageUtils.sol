// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/trade/IJavMultiCollatDiamond.sol";

import "./StorageUtils.sol";
import "./AddressStoreUtils.sol";
import "./CollateralUtils.sol";
import "./TradingCommonUtils.sol";
import "./ConstantsUtils.sol";

/**
 * @custom:version 8
 * @dev JavTradingStorage facet internal library
 */

library TradingStorageUtils {
    uint256 private constant PRICE_PRECISION = 1e10; // 10 decimals
    uint256 private constant MAX_SL_P = 75; // -75% pnl
    uint256 private constant MAX_PNL_P = 900; // 900% pnl (10x)

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function initializeTradingStorage(
        address _rewardsToken,
        address _rewardsDistributor,
        address _borrowingProvider,
        address[] memory _collaterals,
        uint8[] memory _collateralsIndexes
    ) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();
        if (
            _rewardsToken == address(0) ||
            _rewardsDistributor == address(0) ||
            _borrowingProvider == address(0)
        ) revert IGeneralErrors.ZeroAddress();

        if (_collaterals.length < 2) revert ITradingStorageUtils.MissingCollaterals();
        if (_collaterals.length != _collateralsIndexes.length) revert IGeneralErrors.WrongLength();

        // Set addresses
        s.borrowingProvider = _borrowingProvider;
        IJavAddressStore.Addresses storage addresses = AddressStoreUtils.getAddresses();
        addresses.rewardsToken = _rewardsToken;
        addresses.rewardsDistributor = _rewardsDistributor;

        emit IJavAddressStore.AddressesUpdated(addresses);

        // Add collaterals
        for (uint256 i; i < _collaterals.length; ++i) {
            addCollateral(_collaterals[i], _collateralsIndexes[i]);
        }

        // Trading is paused by default for state copy
        updateTradingActivated(ITradingStorage.TradingActivated.PAUSED);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradingActivated(ITradingStorage.TradingActivated _activated) internal {
        _getStorage().tradingActivated = _activated;

        emit ITradingStorageUtils.TradingActivatedUpdated(_activated);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function addCollateral(address _collateral, uint8 _index) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();

        if (s.collateralIndex[_collateral] != 0) revert IGeneralErrors.AlreadyExists();
        if (_collateral == address(0)) revert IGeneralErrors.ZeroAddress();

        CollateralUtils.CollateralConfig memory collateralConfig = CollateralUtils
            .getCollateralConfig(_collateral);

        s.collaterals[_index] = ITradingStorage.Collateral({
            collateral: _collateral,
            isActive: true,
            __placeholder: 0,
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });

        s.collateralIndex[_collateral] = _index;
        s.lastCollateralIndex = _index;

        // Setup collateral approvals
        IERC20 collateral = IERC20(_collateral);
        collateral.approve(_getMultiCollatDiamond().getBorrowingProvider(), type(uint256).max);

        emit ITradingStorageUtils.CollateralAdded(_collateral, _index);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function toggleCollateralActiveState(uint8 _collateralIndex) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Collateral storage collateral = s.collaterals[_collateralIndex];

        if (collateral.precision == 0) revert IGeneralErrors.DoesntExist();

        bool toggled = !collateral.isActive;
        collateral.isActive = toggled;

        emit ITradingStorageUtils.CollateralUpdated(_collateralIndex, toggled);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function storeTrade(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.TradeInfo memory _tradeInfo
    ) internal returns (ITradingStorage.Trade memory) {
        ITradingStorage.TradingStorage storage s = _getStorage();

        validateTrade(_trade);

        if (_trade.tradeType != ITradingStorage.TradeType.TRADE && _tradeInfo.maxSlippageP == 0)
            revert ITradingStorageUtils.MaxSlippageZero();

        if (
            _trade.tradeType == ITradingStorage.TradeType.TRADE &&
            _tradeInfo.collateralPriceUsd == 0
        ) revert ITradingStorageUtils.TradeInfoCollateralPriceUsdZero();

        ITradingStorage.Counter memory counter = s.userCounters[_trade.user];

        _trade.index = counter.currentIndex;
        _trade.isOpen = true;
        _trade.tp = _limitTpDistance(_trade.openPrice, _trade.leverage, _trade.tp, _trade.long);
        _trade.sl = _limitSlDistance(_trade.openPrice, _trade.leverage, _trade.sl, _trade.long);

        _tradeInfo.createdBlock = uint32(block.number);
        _tradeInfo.tpLastUpdatedBlock = _tradeInfo.createdBlock;
        _tradeInfo.slLastUpdatedBlock = _tradeInfo.createdBlock;
        _tradeInfo.lastOiUpdateTs = uint48(block.timestamp);

        counter.currentIndex++;
        counter.openCount++;

        s.trades[_trade.user][_trade.index] = _trade;
        s.tradeInfos[_trade.user][_trade.index] = _tradeInfo;
        s.userCounters[_trade.user] = counter;

        if (!s.traderStored[_trade.user]) {
            s.traders.push(_trade.user);
            s.traderStored[_trade.user] = true;
        }

        emit ITradingStorageUtils.TradeStored(_trade, _tradeInfo);

        return _trade;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradeCollateralAmount(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount
    ) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();
        if (_collateralAmount == 0) revert ITradingStorageUtils.TradePositionSizeZero();

        t.collateralAmount = _collateralAmount;

        emit ITradingStorageUtils.TradeCollateralUpdated(_tradeId, _collateralAmount);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradePosition(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount,
        uint24 _leverage,
        uint64 _openPrice
    ) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();
        if (_collateralAmount * _leverage == 0) revert ITradingStorageUtils.TradePositionSizeZero();
        if (_openPrice == 0) revert ITradingStorageUtils.TradeOpenPriceZero();

        TradingCommonUtils.handleOiDelta(
            t,
            TradingCommonUtils.getPositionSizeCollateral(_collateralAmount, _leverage)
        );

        t.collateralAmount = _collateralAmount;
        t.leverage = _leverage;
        t.openPrice = _openPrice;
        t.tp = _limitTpDistance(t.openPrice, t.leverage, t.tp, t.long);
        t.sl = _limitSlDistance(t.openPrice, t.leverage, t.sl, t.long);

        uint32 blockNumber = uint32(block.number);
        i.createdBlock = blockNumber;
        i.tpLastUpdatedBlock = blockNumber;
        i.slLastUpdatedBlock = blockNumber;

        emit ITradingStorageUtils.TradePositionUpdated(
            _tradeId,
            _collateralAmount,
            t.leverage,
            t.openPrice,
            t.tp,
            t.sl
        );
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateOpenOrderDetails(
        ITradingStorage.Id memory _tradeId,
        uint64 _openPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();

        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo memory i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType == ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();
        if (_openPrice == 0) revert ITradingStorageUtils.TradeOpenPriceZero();
        if (_tp > 0 && (t.long ? _tp <= _openPrice : _tp >= _openPrice))
            revert ITradingStorageUtils.TradeTpInvalid();
        if (_sl > 0 && (t.long ? _sl >= _openPrice : _sl <= _openPrice))
            revert ITradingStorageUtils.TradeSlInvalid();
        if (_maxSlippageP == 0) revert ITradingStorageUtils.MaxSlippageZero();

        _tp = _limitTpDistance(_openPrice, t.leverage, _tp, t.long);
        _sl = _limitSlDistance(_openPrice, t.leverage, _sl, t.long);

        t.openPrice = _openPrice;
        t.tp = _tp;
        t.sl = _sl;

        i.maxSlippageP = _maxSlippageP;
        i.createdBlock = uint32(block.number);
        i.tpLastUpdatedBlock = i.createdBlock;
        i.slLastUpdatedBlock = i.createdBlock;

        s.tradeInfos[_tradeId.user][_tradeId.index] = i;

        emit ITradingStorageUtils.OpenOrderDetailsUpdated(
            _tradeId,
            _openPrice,
            _tp,
            _sl,
            _maxSlippageP
        );
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradeTp(ITradingStorage.Id memory _tradeId, uint64 _newTp) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();

        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();

        _newTp = _limitTpDistance(t.openPrice, t.leverage, _newTp, t.long);

        t.tp = _newTp;
        i.tpLastUpdatedBlock = uint32(block.number);

        emit ITradingStorageUtils.TradeTpUpdated(_tradeId, _newTp);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradeSl(ITradingStorage.Id memory _tradeId, uint64 _newSl) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();

        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();

        _newSl = _limitSlDistance(t.openPrice, t.leverage, _newSl, t.long);

        t.sl = _newSl;
        i.slLastUpdatedBlock = uint32(block.number);

        emit ITradingStorageUtils.TradeSlUpdated(_tradeId, _newSl);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function closeTrade(ITradingStorage.Id memory _tradeId) internal {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();

        t.isOpen = false;
        s.userCounters[_tradeId.user].openCount--;

        emit ITradingStorageUtils.TradeClosed(_tradeId);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollateral(uint8 _index) internal view returns (ITradingStorage.Collateral memory) {
        return _getStorage().collaterals[_index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function isCollateralActive(uint8 _index) internal view returns (bool) {
        return _getStorage().collaterals[_index].isActive;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function isCollateralListed(uint8 _index) internal view returns (bool) {
        return _getStorage().collaterals[_index].precision > 0;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollateralsCount() internal view returns (uint8) {
        return _getStorage().lastCollateralIndex + 1;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollaterals() internal view returns (ITradingStorage.Collateral[] memory) {
        ITradingStorage.TradingStorage storage s = _getStorage();
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
    function getCollateralIndex(address _collateral) internal view returns (uint8) {
        return _getStorage().collateralIndex[_collateral];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradingActivated() internal view returns (ITradingStorage.TradingActivated) {
        return _getStorage().tradingActivated;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTraderStored(address _trader) internal view returns (bool) {
        return _getStorage().traderStored[_trader];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTraders(uint32 _offset, uint32 _limit) internal view returns (address[] memory) {
        ITradingStorage.TradingStorage storage s = _getStorage();

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
    function getTrade(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.Trade memory) {
        return _getStorage().trades[_trader][_index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTrades(address _trader) internal view returns (ITradingStorage.Trade[] memory) {
        ITradingStorage.TradingStorage storage s = _getStorage();
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
    ) internal view returns (ITradingStorage.Trade[] memory) {
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
    function getTradeInfo(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.TradeInfo memory) {
        return _getStorage().tradeInfos[_trader][_index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradeInfos(
        address _trader
    ) internal view returns (ITradingStorage.TradeInfo[] memory) {
        ITradingStorage.TradingStorage storage s = _getStorage();
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
    ) internal view returns (ITradingStorage.TradeInfo[] memory) {
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
    function getCounters(address _trader) internal view returns (ITradingStorage.Counter memory) {
        return _getStorage().userCounters[_trader];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
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
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getBorrowingProvider() internal view returns (address) {
        return _getStorage().borrowingProvider;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getPnlPercent(
        uint64 _openPrice,
        uint64 _currentPrice,
        bool _long,
        uint24 _leverage
    ) internal pure returns (int256 p) {
        int256 pricePrecision = int256(PRICE_PRECISION);
        int256 maxPnlP = int256(MAX_PNL_P) * pricePrecision;
        int256 minPnlP = -100 * int256(PRICE_PRECISION);

        int256 openPrice = int256(uint256(_openPrice));
        int256 currentPrice = int256(uint256(_currentPrice));
        int256 leverage = int256(uint256(_leverage));

        p = _openPrice > 0
            ? ((_long ? currentPrice - openPrice : openPrice - currentPrice) *
                100 *
                pricePrecision *
                leverage) /
                openPrice /
                1e3
            : int256(0);

        p = p > maxPnlP ? maxPnlP : p < minPnlP ? minPnlP : p;
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRADING_STORAGE_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (ITradingStorage.TradingStorage storage s) {
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

    /**
     * @dev Limits take profit price distance for long/short based on '_openPrice', '_tp, '_leverage' and sets an automatic TP if '_tp' is zero.
     * @param _openPrice trade open price (1e10 precision)
     * @param _leverage trade leverage (1e3 precision)
     * @param _tp trade take profit price (1e10 precision)
     * @param _long trade direction
     */
    function _limitTpDistance(
        uint64 _openPrice,
        uint24 _leverage,
        uint64 _tp,
        bool _long
    ) internal pure returns (uint64) {
        if (
            _tp == 0 ||
            getPnlPercent(_openPrice, _tp, _long, _leverage) ==
            int256(MAX_PNL_P) * int256(PRICE_PRECISION)
        ) {
            uint256 openPrice = uint256(_openPrice);
            uint256 tpDiff = (openPrice * MAX_PNL_P * 1e3) / _leverage / 100;
            uint256 newTp = _long
                ? openPrice + tpDiff
                : (tpDiff <= openPrice ? openPrice - tpDiff : 0);
            uint64 maxTp = type(uint64).max;
            return newTp > maxTp ? maxTp : uint64(newTp);
        }

        return _tp;
    }

    /**
     * @dev Limits stop loss price distance for long/short based on '_openPrice', '_sl, '_leverage'.
     * @param _openPrice trade open price (1e10 precision)
     * @param _leverage trade leverage (1e3 precision)
     * @param _sl trade stop loss price (1e10 precision)
     * @param _long trade direction
     */
    function _limitSlDistance(
        uint64 _openPrice,
        uint24 _leverage,
        uint64 _sl,
        bool _long
    ) internal pure returns (uint64) {
        if (
            _sl > 0 &&
            getPnlPercent(_openPrice, _sl, _long, _leverage) <
            int256(MAX_SL_P) * int256(PRICE_PRECISION) * -1
        ) {
            uint256 openPrice = uint256(_openPrice);
            uint256 slDiff = (openPrice * MAX_SL_P * 1e3) / _leverage / 100;
            uint256 newSl = _long ? openPrice - slDiff : openPrice + slDiff;

            // Here an overflow (for shorts) is actually impossible because _sl is uint64
            // And the new stop loss is always closer (= lower for shorts) than the _sl input

            return uint64(newSl);
        }

        return _sl;
    }

    /**
     * @dev Validation for trade struct (used by storeTrade and storePendingOrder for market open orders)
     * @param _trade trade struct to validate
     */
    function validateTrade(ITradingStorage.Trade memory _trade) internal view {
        if (_trade.user == address(0)) revert IGeneralErrors.ZeroAddress();

        if (!_getMultiCollatDiamond().isPairIndexListed(_trade.pairIndex))
            revert ITradingStorageUtils.TradePairNotListed();

        if (uint256(_trade.collateralAmount) * _trade.leverage == 0)
            revert ITradingStorageUtils.TradePositionSizeZero();

        if (!isCollateralActive(_trade.collateralIndex))
            revert IGeneralErrors.InvalidCollateralIndex();

        if (_trade.openPrice == 0) revert ITradingStorageUtils.TradeOpenPriceZero();

        if (
            _trade.tp != 0 &&
            (_trade.long ? _trade.tp <= _trade.openPrice : _trade.tp >= _trade.openPrice)
        ) revert ITradingStorageUtils.TradeTpInvalid();

        if (
            _trade.sl != 0 &&
            (_trade.long ? _trade.sl >= _trade.openPrice : _trade.sl <= _trade.openPrice)
        ) revert ITradingStorageUtils.TradeSlInvalid();
    }
}
