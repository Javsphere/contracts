// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/ITradingProcessingUtils.sol";
import "../interfaces/trade/types/ITradingStorage.sol";
import "../libraries/trade/TradingCloseUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #7: processing (trading processing)
 */
contract JavTradingProcessing is JavAddressStore, ITradingProcessingUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ITradingProcessingUtils
    function initializeTradingProcessing(uint8 _vaultClosingFeeP) external reinitializer(4) {
        TradingCloseUtils.initializeTradingProcessing(_vaultClosingFeeP);
    }

    // Management Setters

    /// @inheritdoc ITradingProcessingUtils
    function updateVaultClosingFeeP(uint8 _valueP) external onlyRole(Role.GOV) {
        TradingCloseUtils.updateVaultClosingFeeP(_valueP);
    }

    /// @inheritdoc ITradingProcessingUtils
    function claimPendingGovFees() external onlyRole(Role.GOV) {
        TradingCloseUtils.claimPendingGovFees();
    }

    // Interactions

    /// @inheritdoc ITradingProcessingUtils
    function openTradeMarketOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingCloseUtils.openTradeMarketOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingProcessingUtils
    function closeTradeMarketOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingCloseUtils.closeTradeMarketOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingProcessingUtils
    function executeTriggerOpenOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingCloseUtils.executeTriggerOpenOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingProcessingUtils
    function executeTriggerCloseOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingCloseUtils.executeTriggerCloseOrder(_pendingOrder);
    }

    // Getters

    /// @inheritdoc ITradingProcessingUtils
    function getVaultClosingFeeP() external view returns (uint8) {
        return TradingCloseUtils.getVaultClosingFeeP();
    }

    /// @inheritdoc ITradingProcessingUtils
    function getPendingGovFeesCollateral(uint8 _collateralIndex) external view returns (uint256) {
        return TradingCloseUtils.getPendingGovFeesCollateral(_collateralIndex);
    }
}
