// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/leverageX/libraries/ITradingProcessingUtils.sol";
import "../interfaces/leverageX/types/ITradingStorage.sol";
import "../libraries/leverageX/TradingProcessingUtils.sol";
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
        TradingProcessingUtils.initializeTradingProcessing(_vaultClosingFeeP);
    }

    // Management Setters

    /// @inheritdoc ITradingProcessingUtils
    function updateVaultClosingFeeP(uint8 _valueP) external onlyRole(Role.GOV) {
        TradingProcessingUtils.updateVaultClosingFeeP(_valueP);
    }

    /// @inheritdoc ITradingProcessingUtils
    function claimPendingGovFees() external onlyRole(Role.GOV) {
        TradingProcessingUtils.claimPendingGovFees();
    }

    // Interactions

    /// @inheritdoc ITradingProcessingUtils
    function openTradeMarketOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingProcessingUtils.openTradeMarketOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingProcessingUtils
    function closeTradeMarketOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingProcessingUtils.closeTradeMarketOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingProcessingUtils
    function executeTriggerOpenOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingProcessingUtils.executeTriggerOpenOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingProcessingUtils
    function executeTriggerCloseOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) external virtual onlySelf {
        TradingProcessingUtils.executeTriggerCloseOrder(_pendingOrder);
    }

    // Getters

    /// @inheritdoc ITradingProcessingUtils
    function getVaultClosingFeeP() external view returns (uint8) {
        return TradingProcessingUtils.getVaultClosingFeeP();
    }

    /// @inheritdoc ITradingProcessingUtils
    function getPendingGovFeesCollateral(uint8 _collateralIndex) external view returns (uint256) {
        return TradingProcessingUtils.getPendingGovFeesCollateral(_collateralIndex);
    }
}
