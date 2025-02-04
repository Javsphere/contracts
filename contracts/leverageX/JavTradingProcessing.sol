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

    /// @inheritdoc ITradingProcessingUtils
    function setTradeUsdThresholds(uint32[] memory _usdThresholds) external onlyRole(Role.GOV) {
        TradingProcessingUtils.setTradeUsdThresholds(_usdThresholds);
    }

    /// @inheritdoc ITradingProcessingUtils
    function setTradeLockDuration(uint16[] memory _duration) external onlyRole(Role.GOV) {
        TradingProcessingUtils.setTradeLockDuration(_duration);
    }

    /// @inheritdoc ITradingProcessingUtils
    function setLimitedGroups(uint8[] memory _limitedGroups) external onlyRole(Role.GOV) {
        TradingProcessingUtils.setLimitedGroups(_limitedGroups);
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

    /// @inheritdoc ITradingProcessingUtils
    function getTradeTimestamp(address _trader, uint256 _tradeId) external view returns (uint256) {
        return TradingProcessingUtils.getTradeTimestamp(_trader, _tradeId);
    }

    /// @inheritdoc ITradingProcessingUtils
    function getTradeUsdThresholds() external view returns (uint32[] memory) {
        return TradingProcessingUtils.getTradeUsdThresholds();
    }

    /// @inheritdoc ITradingProcessingUtils
    function getTradeLockDuration() external view returns (uint16[] memory) {
        return TradingProcessingUtils.getTradeLockDuration();
    }

    /// @inheritdoc ITradingProcessingUtils
    function getLimitedGroups() external view returns (uint8[] memory) {
        return TradingProcessingUtils.getLimitedGroups();
    }

    /// @inheritdoc ITradingProcessingUtils
    function isTradeInLockLimit(address _trader, uint32 _tradeId) external view returns (bool) {
        return TradingProcessingUtils.isTradeInLockLimit(_trader, _tradeId);
    }
}
