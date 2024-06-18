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
        address _referrer
    ) external {
        TradingInteractionsUtils.openTrade(_trade, _maxSlippageP, _referrer);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function closeTradeMarket(uint32 _index) external {
        TradingInteractionsUtils.closeTradeMarket(_index);
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
    function triggerOrder(uint256 _packed) external {
        TradingInteractionsUtils.triggerOrder(_packed);
    }
}
