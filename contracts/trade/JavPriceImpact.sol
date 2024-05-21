// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/IPriceImpactUtils.sol";
import "../libraries/trade/PriceImpactUtils.sol";
import "../libraries/trade/PairsStorageUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #4: Price impact OI windows
 */
contract JavPriceImpact is JavAddressStore, IPriceImpactUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPriceImpactUtils
    function initializePriceImpact(
        uint48 _windowsDuration,
        uint48 _windowsCount
    ) external reinitializer(5) {
        PriceImpactUtils.initializePriceImpact(_windowsDuration, _windowsCount);
    }

    // Management Setters

    /// @inheritdoc IPriceImpactUtils
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) external onlyRole(Role.GOV) {
        PriceImpactUtils.setPriceImpactWindowsCount(_newWindowsCount);
    }

    /// @inheritdoc IPriceImpactUtils
    function setPriceImpactWindowsDuration(uint48 _newWindowsDuration) external onlyRole(Role.GOV) {
        PriceImpactUtils.setPriceImpactWindowsDuration(
            _newWindowsDuration,
            PairsStorageUtils.pairsCount()
        );
    }

    /// @inheritdoc IPriceImpactUtils
    function setPairDepths(
        uint256[] calldata _indices,
        uint128[] calldata _depthsAboveUsd,
        uint128[] calldata _depthsBelowUsd
    ) external onlyRole(Role.MANAGER) {
        PriceImpactUtils.setPairDepths(_indices, _depthsAboveUsd, _depthsBelowUsd);
    }

    // Interactions

    /// @inheritdoc IPriceImpactUtils
    function addPriceImpactOpenInterest(
        uint256 _openInterestUsd,
        uint256 _pairIndex,
        bool _long
    ) external virtual onlySelf {
        PriceImpactUtils.addPriceImpactOpenInterest(uint128(_openInterestUsd), _pairIndex, _long);
    }

    /// @inheritdoc IPriceImpactUtils
    function removePriceImpactOpenInterest(
        uint256 _openInterestUsd,
        uint256 _pairIndex,
        bool _long,
        uint48 _addTs
    ) external virtual onlySelf {
        PriceImpactUtils.removePriceImpactOpenInterest(
            uint128(_openInterestUsd),
            _pairIndex,
            _long,
            _addTs
        );
    }

    // Getters

    /// @inheritdoc IPriceImpactUtils
    function getPriceImpactOi(
        uint256 _pairIndex,
        bool _long
    ) external view returns (uint256 activeOi) {
        return PriceImpactUtils.getPriceImpactOi(_pairIndex, _long);
    }

    /// @inheritdoc IPriceImpactUtils
    function getTradePriceImpact(
        uint256 _openPrice,
        uint256 _pairIndex,
        bool _long,
        uint256 _tradeOpenInterestUsd
    ) external view returns (uint256 priceImpactP, uint256 priceAfterImpact) {
        (priceImpactP, priceAfterImpact) = PriceImpactUtils.getTradePriceImpact(
            _openPrice,
            _pairIndex,
            _long,
            _tradeOpenInterestUsd
        );
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairDepth(uint256 _pairIndex) external view returns (PairDepth memory) {
        return PriceImpactUtils.getPairDepth(_pairIndex);
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindowsSettings() external view returns (OiWindowsSettings memory) {
        return PriceImpactUtils.getOiWindowsSettings();
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindow(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256 _windowId
    ) external view returns (PairOi memory) {
        return PriceImpactUtils.getOiWindow(_windowsDuration, _pairIndex, _windowId);
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindows(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256[] calldata _windowIds
    ) external view returns (PairOi[] memory) {
        return PriceImpactUtils.getOiWindows(_windowsDuration, _pairIndex, _windowIds);
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairDepths(uint256[] calldata _indices) external view returns (PairDepth[] memory) {
        return PriceImpactUtils.getPairDepths(_indices);
    }
}
