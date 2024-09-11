// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/ITradingInteractionsUtils.sol";
import "../interfaces/trade/types/ITradingStorage.sol";
import "../libraries/trade/TradingInteractionsUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #6: Trading (user interactions)
 */
contract JavTradingInteractions is JavAddressStore, ITradingInteractionsUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Interactions

    /// @inheritdoc ITradingInteractionsUtils
    function openTrade(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer,
        bytes[][] calldata _priceUpdate
    ) external payable {
        TradingInteractionsUtils.openTrade(_trade, _maxSlippageP, _referrer, _priceUpdate);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function updateMaxClosingSlippageP(uint32 _index, uint16 _maxSlippageP) external {
        TradingInteractionsUtils.updateMaxClosingSlippageP(_index, _maxSlippageP);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function closeTradeMarket(uint32 _index, bytes[][] calldata _priceUpdate) external payable {
        TradingInteractionsUtils.closeTradeMarket(_index, _priceUpdate);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function updateOpenOrder(
        uint32 _index,
        uint64 _triggerPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) external {
        TradingInteractionsUtils.updateOpenOrder(_index, _triggerPrice, _tp, _sl, _maxSlippageP);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function cancelOpenOrder(uint32 _index) external {
        TradingInteractionsUtils.cancelOpenOrder(_index);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function updateTp(uint32 _index, uint64 _newTp) external {
        TradingInteractionsUtils.updateTp(_index, _newTp);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function updateSl(uint32 _index, uint64 _newSl) external {
        TradingInteractionsUtils.updateSl(_index, _newSl);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function updateLeverage(
        uint32 _index,
        uint24 _newLeverage,
        bytes[][] calldata _priceUpdate
    ) external payable {
        TradingInteractionsUtils.updateLeverage(_index, _newLeverage, _priceUpdate);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function increasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        uint64 _expectedPrice,
        uint16 _maxSlippageP,
        bytes[][] calldata _priceUpdate
    ) external payable {
        TradingInteractionsUtils.increasePositionSize(
            _index,
            _collateralDelta,
            _leverageDelta,
            _expectedPrice,
            _maxSlippageP,
            _priceUpdate
        );
    }

    /// @inheritdoc ITradingInteractionsUtils
    function decreasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        bytes[][] calldata _priceUpdate
    ) external payable {
        TradingInteractionsUtils.decreasePositionSize(
            _index,
            _collateralDelta,
            _leverageDelta,
            _priceUpdate
        );
    }

    /// @inheritdoc ITradingInteractionsUtils
    function triggerOrder(uint256 _packed, bytes[][] calldata _priceUpdate) external payable {
        TradingInteractionsUtils.triggerOrder(_packed, _priceUpdate);
    }
}
