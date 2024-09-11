// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/IPriceAggregatorUtils.sol";
import "../libraries/trade/PriceAggregatorUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #9: Price aggregator
 */
contract JavPriceAggregator is JavAddressStore, IPriceAggregatorUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function initializePriceAggregator(
        IJavPriceAggregator _oracle,
        IJavPriceAggregator _alternativeOracle,
        bytes32 _rewardsTokenUsdFeed,
        uint8[] calldata _collateralIndices,
        bytes32[] memory _collateralUsdPriceFeeds
    ) external reinitializer(8) {
        PriceAggregatorUtils.initializePriceAggregator(
            _oracle,
            _alternativeOracle,
            _rewardsTokenUsdFeed,
            _collateralIndices,
            _collateralUsdPriceFeeds
        );
    }

    // Management Setters

    /// @inheritdoc IPriceAggregatorUtils
    function updateCollateralUsdPriceFeed(
        uint8 _collateralIndex,
        bytes32 _value
    ) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.updateCollateralUsdPriceFeed(_collateralIndex, _value);
    }

    // Interactions

    /// @inheritdoc IPriceAggregatorUtils
    function getPrice(uint16 _pairIndex) external view virtual returns (uint256) {
        return PriceAggregatorUtils.getPrice(_pairIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function updatePrices(
        bytes[][] calldata _priceUpdate,
        address _user
    ) external payable onlySelf {
        PriceAggregatorUtils.updatePrices(_priceUpdate, _user);
    }

    // Getters

    /// @inheritdoc IPriceAggregatorUtils
    function getCollateralPriceUsd(uint8 _collateralIndex) external view returns (uint256) {
        return PriceAggregatorUtils.getCollateralPriceUsd(_collateralIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getCollateralFeed(uint8 _collateralIndex) external view returns (bytes32) {
        return PriceAggregatorUtils.getCollateralFeed(_collateralIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getRewardsTokenUsdFeed() external view returns (bytes32) {
        return PriceAggregatorUtils.getRewardsTokenUsdFeed();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _collateralValue
    ) external view returns (uint256) {
        return PriceAggregatorUtils.getUsdNormalizedValue(_collateralIndex, _collateralValue);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getCollateralFromUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _normalizedValue
    ) external view returns (uint256) {
        return
            PriceAggregatorUtils.getCollateralFromUsdNormalizedValue(
                _collateralIndex,
                _normalizedValue
            );
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getRewardsTokenPriceUsd() external view returns (uint256) {
        return PriceAggregatorUtils.getRewardsTokenPriceUsd();
    }
}
