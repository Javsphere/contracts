// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/ITradingInteractionsUtils.sol";
import "../interfaces/trade/types/ITradingStorage.sol";
import "../libraries/trade/TradingInteractionsUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #7: Trading (user interactions)
 */
contract JavTradingInteractions is JavAddressStore, ITradingInteractionsUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ITradingInteractionsUtils
    function initializeTrading(
        uint16 _marketOrdersTimeoutBlocks,
        address[] memory _usersByPassTriggerLink
    ) external reinitializer(8) {
        TradingInteractionsUtils.initializeTrading(
            _marketOrdersTimeoutBlocks,
            _usersByPassTriggerLink
        );
    }

    // Management Setters

    /// @inheritdoc ITradingInteractionsUtils
    function updateMarketOrdersTimeoutBlocks(uint16 _valueBlocks) external onlyRole(Role.GOV) {
        TradingInteractionsUtils.updateMarketOrdersTimeoutBlocks(_valueBlocks);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function updateByPassTriggerLink(
        address[] memory _users,
        bool[] memory _shouldByPass
    ) external onlyRole(Role.GOV) {
        TradingInteractionsUtils.updateByPassTriggerLink(_users, _shouldByPass);
    }

    // Interactions

    /// @inheritdoc ITradingInteractionsUtils
    function setTradingDelegate(address _delegate) external {
        TradingInteractionsUtils.setTradingDelegate(_delegate);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function removeTradingDelegate() external {
        TradingInteractionsUtils.removeTradingDelegate();
    }

    /// @inheritdoc ITradingInteractionsUtils
    function delegatedTradingAction(
        address _trader,
        bytes calldata _callData
    ) external returns (bytes memory) {
        return TradingInteractionsUtils.delegatedTradingAction(_trader, _callData);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function openTrade(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer
    ) external {
        TradingInteractionsUtils.openTrade(_trade, _maxSlippageP, _referrer);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function openTradeNative(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer
    ) external payable {
        TradingInteractionsUtils.openTradeNative(_trade, _maxSlippageP, _referrer);
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

    /// @inheritdoc ITradingInteractionsUtils
    function openTradeMarketTimeout(ITradingStorage.Id memory _orderId) external {
        TradingInteractionsUtils.openTradeMarketTimeout(_orderId);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function closeTradeMarketTimeout(ITradingStorage.Id memory _orderId) external {
        TradingInteractionsUtils.closeTradeMarketTimeout(_orderId);
    }

    // Getters

    /// @inheritdoc ITradingInteractionsUtils
    function getWrappedNativeToken() external view returns (address) {
        return TradingInteractionsUtils.getWrappedNativeToken();
    }

    /// @inheritdoc ITradingInteractionsUtils
    function isWrappedNativeToken(address _token) external view returns (bool) {
        return TradingInteractionsUtils.isWrappedNativeToken(_token);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function getTradingDelegate(address _trader) external view returns (address) {
        return TradingInteractionsUtils.getTradingDelegate(_trader);
    }

    /// @inheritdoc ITradingInteractionsUtils
    function getMarketOrdersTimeoutBlocks() external view returns (uint16) {
        return TradingInteractionsUtils.getMarketOrdersTimeoutBlocks();
    }

    /// @inheritdoc ITradingInteractionsUtils
    function getByPassTriggerLink(address _user) external view returns (bool) {
        return TradingInteractionsUtils.getByPassTriggerLink(_user);
    }
}
