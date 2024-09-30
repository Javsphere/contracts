// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/ITradingStorageUtils.sol";

import "../libraries/trade/TradingStorageUtils.sol";
import "./abstract/JavAddressStore.sol";
import "../libraries/trade/ArrayGetters.sol";

/**
 * @custom:version 8
 * @dev Facet #5: Trading storage
 */
contract JavTradingStorage is JavAddressStore, ITradingStorageUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ITradingStorageUtils
    function initializeTradingStorage(
        address _rewardsToken,
        address _rewardsDistributor,
        address _borrowingProvider,
        address[] memory _collaterals,
        uint8[] memory _collateralsIndexes
    ) external reinitializer(7) {
        TradingStorageUtils.initializeTradingStorage(
            _rewardsToken,
            _rewardsDistributor,
            _borrowingProvider,
            _collaterals,
            _collateralsIndexes
        );
    }

    // Management Setters

    /// @inheritdoc ITradingStorageUtils
    function updateTradingActivated(TradingActivated _activated) external onlyRole(Role.GOV) {
        TradingStorageUtils.updateTradingActivated(_activated);
    }

    /// @inheritdoc ITradingStorageUtils
    function addCollateral(address _collateral, uint8 _index) external onlyRole(Role.GOV) {
        TradingStorageUtils.addCollateral(_collateral, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function toggleCollateralActiveState(uint8 _collateralIndex) external onlyRole(Role.GOV) {
        TradingStorageUtils.toggleCollateralActiveState(_collateralIndex);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateBorrowingProvider(address _borrowingProvider) external onlyRole(Role.GOV) {
        TradingStorageUtils.updateBorrowingProvider(_borrowingProvider);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateCollateralApprove(uint8 _collateralIndex) external onlyRole(Role.GOV) {
        TradingStorageUtils.updateCollateralApprove(_collateralIndex);
    }

    // Interactions

    /// @inheritdoc ITradingStorageUtils
    function storeTrade(
        Trade memory _trade,
        TradeInfo memory _tradeInfo
    ) external virtual onlySelf returns (Trade memory) {
        return TradingStorageUtils.storeTrade(_trade, _tradeInfo);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeMaxClosingSlippageP(
        ITradingStorage.Id memory _tradeId,
        uint16 _maxSlippageP
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradeMaxClosingSlippageP(_tradeId, _maxSlippageP);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeCollateralAmount(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradeCollateralAmount(_tradeId, _collateralAmount);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradePosition(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount,
        uint24 _leverage,
        uint64 _openPrice,
        bool _isPartialIncrease
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradePosition(
            _tradeId,
            _collateralAmount,
            _leverage,
            _openPrice,
            _isPartialIncrease
        );
    }

    /// @inheritdoc ITradingStorageUtils
    function updateOpenOrderDetails(
        ITradingStorage.Id memory _tradeId,
        uint64 _openPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) external virtual onlySelf {
        TradingStorageUtils.updateOpenOrderDetails(_tradeId, _openPrice, _tp, _sl, _maxSlippageP);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeTp(Id memory _tradeId, uint64 _newTp) external virtual onlySelf {
        TradingStorageUtils.updateTradeTp(_tradeId, _newTp);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeSl(Id memory _tradeId, uint64 _newSl) external virtual onlySelf {
        TradingStorageUtils.updateTradeSl(_tradeId, _newSl);
    }

    /// @inheritdoc ITradingStorageUtils
    function closeTrade(Id memory _tradeId) external virtual onlySelf {
        TradingStorageUtils.closeTrade(_tradeId);
    }

    // Getters

    /// @inheritdoc ITradingStorageUtils
    function getCollateral(uint8 _index) external view returns (Collateral memory) {
        return TradingStorageUtils.getCollateral(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function isCollateralActive(uint8 _index) external view returns (bool) {
        return TradingStorageUtils.isCollateralActive(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function isCollateralListed(uint8 _index) external view returns (bool) {
        return TradingStorageUtils.isCollateralListed(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getCollateralsCount() external view returns (uint8) {
        return TradingStorageUtils.getCollateralsCount();
    }

    /// @inheritdoc ITradingStorageUtils
    function getCollaterals() external view returns (Collateral[] memory) {
        return ArrayGetters.getCollaterals();
    }

    /// @inheritdoc ITradingStorageUtils
    function getCollateralIndex(address _collateral) external view returns (uint8) {
        return TradingStorageUtils.getCollateralIndex(_collateral);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradingActivated() external view returns (TradingActivated) {
        return TradingStorageUtils.getTradingActivated();
    }

    /// @inheritdoc ITradingStorageUtils
    function getTraderStored(address _trader) external view returns (bool) {
        return TradingStorageUtils.getTraderStored(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTraders(uint32 _offset, uint32 _limit) external view returns (address[] memory) {
        return ArrayGetters.getTraders(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTrade(address _trader, uint32 _index) external view returns (Trade memory) {
        return TradingStorageUtils.getTrade(_trader, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTrades(address _trader) external view returns (Trade[] memory) {
        return ArrayGetters.getTrades(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTrades(uint256 _offset, uint256 _limit) external view returns (Trade[] memory) {
        return ArrayGetters.getAllTrades(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradeInfo(address _trader, uint32 _index) external view returns (TradeInfo memory) {
        return TradingStorageUtils.getTradeInfo(_trader, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradeInfos(address _trader) external view returns (TradeInfo[] memory) {
        return ArrayGetters.getTradeInfos(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradeInfos(
        uint256 _offset,
        uint256 _limit
    ) external view returns (TradeInfo[] memory) {
        return ArrayGetters.getAllTradeInfos(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getCounters(address _trader) external view returns (Counter memory) {
        return TradingStorageUtils.getCounters(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getBorrowingProvider() external view returns (address) {
        return TradingStorageUtils.getBorrowingProvider();
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradeLiquidationParams(
        address _trader,
        uint32 _index
    ) external view returns (IPairsStorage.GroupLiquidationParams memory) {
        return TradingStorageUtils.getTradeLiquidationParams(_trader, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradesLiquidationParams(
        address _trader
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        return ArrayGetters.getTradesLiquidationParams(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradesLiquidationParams(
        uint256 _offset,
        uint256 _limit
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        return ArrayGetters.getAllTradesLiquidationParams(_offset, _limit);
    }
}
