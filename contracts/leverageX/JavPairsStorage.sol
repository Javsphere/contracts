// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./abstract/JavAddressStore.sol";

import "../libraries/leverageX/PairsStorageUtils.sol";
import "../interfaces/leverageX/libraries/IPairsStorageUtils.sol";

/**
 * @custom:version 8
 * @dev Facet #1: Pairs storage
 */
contract JavPairsStorage is JavAddressStore, IPairsStorageUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPairsStorageUtils
    function initializeGroupLiquidationParams(
        IPairsStorage.GroupLiquidationParams[] memory _groupLiquidationParams
    ) external reinitializer(5) {
        PairsStorageUtils.initializeGroupLiquidationParams(_groupLiquidationParams);
    }

    // Management Setters

    /// @inheritdoc IPairsStorageUtils
    function addPairs(Pair[] calldata _pairs) external onlyRole(Role.GOV) {
        PairsStorageUtils.addPairs(_pairs);
    }

    /// @inheritdoc IPairsStorageUtils
    function updatePairs(
        uint256[] calldata _pairIndices,
        Pair[] calldata _pairs
    ) external onlyRole(Role.GOV) {
        PairsStorageUtils.updatePairs(_pairIndices, _pairs);
    }

    /// @inheritdoc IPairsStorageUtils
    function removePairs(uint256[] calldata _pairIndices) external onlyRole(Role.GOV) {
        PairsStorageUtils.removePairs(_pairIndices);
    }

    /// @inheritdoc IPairsStorageUtils
    function addGroups(Group[] calldata _groups) external onlyRole(Role.GOV) {
        PairsStorageUtils.addGroups(_groups);
    }

    /// @inheritdoc IPairsStorageUtils
    function updateGroups(
        uint256[] calldata _ids,
        Group[] calldata _groups
    ) external onlyRole(Role.GOV) {
        PairsStorageUtils.updateGroups(_ids, _groups);
    }

    /// @inheritdoc IPairsStorageUtils
    function addFees(Fee[] calldata _fees) external onlyRole(Role.GOV) {
        PairsStorageUtils.addFees(_fees);
    }

    /// @inheritdoc IPairsStorageUtils
    function updateFees(uint256[] calldata _ids, Fee[] calldata _fees) external onlyRole(Role.GOV) {
        PairsStorageUtils.updateFees(_ids, _fees);
    }

    /// @inheritdoc IPairsStorageUtils
    function setPairCustomMaxLeverages(
        uint256[] calldata _indices,
        uint256[] calldata _values
    ) external onlyRole(Role.MANAGER) {
        PairsStorageUtils.setPairCustomMaxLeverages(_indices, _values);
    }

    /// @inheritdoc IPairsStorageUtils
    function setGroupLiquidationParams(
        uint256 _groupIndex,
        IPairsStorage.GroupLiquidationParams memory _params
    ) external onlyRole(Role.GOV) {
        PairsStorageUtils.setGroupLiquidationParams(_groupIndex, _params);
    }

    // Getters

    /// @inheritdoc IPairsStorageUtils
    function pairFeed(uint256 _pairIndex) external view returns (bytes32) {
        return PairsStorageUtils.pairFeed(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function isPairListed(string calldata _from, string calldata _to) external view returns (bool) {
        return PairsStorageUtils.isPairListed(_from, _to);
    }

    /// @inheritdoc IPairsStorageUtils
    function isPairIndexListed(uint256 _pairIndex) external view returns (bool) {
        return PairsStorageUtils.isPairIndexListed(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairs(uint256 _index) external view returns (Pair memory) {
        return PairsStorageUtils.pairs(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairsCount() external view returns (uint256) {
        return PairsStorageUtils.pairsCount();
    }

    /// @inheritdoc IPairsStorageUtils
    function pairSpreadP(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairSpreadP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMinLeverage(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairMinLeverage(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairOpenFeeP(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairOpenFeeP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairCloseFeeP(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairCloseFeeP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairTriggerOrderFeeP(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairTriggerOrderFeeP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMinPositionSizeUsd(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairMinPositionSizeUsd(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMinFeeUsd(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairMinFeeUsd(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function groups(uint256 _index) external view returns (Group memory) {
        return PairsStorageUtils.groups(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function groupsCount() external view returns (uint256) {
        return PairsStorageUtils.groupsCount();
    }

    /// @inheritdoc IPairsStorageUtils
    function fees(uint256 _index) external view returns (Fee memory) {
        return PairsStorageUtils.fees(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function feesCount() external view returns (uint256) {
        return PairsStorageUtils.feesCount();
    }

    /// @inheritdoc IPairsStorageUtils
    function pairsBackend(
        uint256 _index
    ) external view returns (Pair memory, Group memory, Fee memory) {
        return PairsStorageUtils.pairsBackend(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMaxLeverage(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairMaxLeverage(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairCustomMaxLeverage(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairCustomMaxLeverage(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function getAllPairsRestrictedMaxLeverage() external view returns (uint256[] memory) {
        return PairsStorageUtils.getAllPairsRestrictedMaxLeverage();
    }

    /// @inheritdoc IPairsStorageUtils
    function getGroupLiquidationParams(
        uint256 _groupIndex
    ) external view returns (IPairsStorage.GroupLiquidationParams memory) {
        return PairsStorageUtils.getGroupLiquidationParams(_groupIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function getPairLiquidationParams(
        uint256 _pairIndex
    ) external view returns (IPairsStorage.GroupLiquidationParams memory) {
        return PairsStorageUtils.getPairLiquidationParams(_pairIndex);
    }
}
