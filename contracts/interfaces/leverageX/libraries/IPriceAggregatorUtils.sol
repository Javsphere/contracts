// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/IPriceAggregator.sol";
import "../types/ITradingStorage.sol";

/**
 * @custom:version 8
 * @dev Interface for JavPriceAggregator facet (inherits types and also contains functions, events, and custom errors)
 */
interface IPriceAggregatorUtils is IPriceAggregator {
    /**
     * @dev Initializes price aggregator facet
     * @param _oracle jav price aggregator oracle addresses
     * @param _collateralIndices collateral indices
     * @param _collateralUsdPriceFeeds corresponding collateral/USD price feeds
     */
    function initializePriceAggregator(
        IJavPriceAggregator _oracle,
        IJavPriceAggregator _alternativeOracle,
        bytes32 _rewardsTokenUsdFeed,
        uint8[] calldata _collateralIndices,
        bytes32[] memory _collateralUsdPriceFeeds
    ) external;

    /**
     * @dev Updates collateral/USD price feed
     * @param _collateralIndex collateral index
     * @param _value new value
     */
    function updateCollateralUsdPriceFeed(uint8 _collateralIndex, bytes32 _value) external;

    /**
     * @dev Requests price from oracles
     * @param _pairIndex pair index
     */
    function getPrice(uint16 _pairIndex) external returns (uint256);

    /**
     * @dev Function to update prices
     * @param _priceUpdate Array of price update data.
     * @param _user user address
     */
    function updatePrices(bytes[][] calldata _priceUpdate, address _user) external payable;

    /**
     * @dev Returns collateral/USD price
     * @param _collateralIndex index of collateral
     */
    function getCollateralPriceUsd(uint8 _collateralIndex) external view returns (uint256);

    /**
     * @dev Returns collateral price feed
     * @param _collateralIndex index of collateral
     */
    function getCollateralFeed(uint8 _collateralIndex) external view returns (bytes32);

    /**
     * @dev Returns rewards token price feed
     */
    function getRewardsTokenUsdFeed() external view returns (bytes32);

    /**
     * @dev Returns USD normalized value from collateral value
     * @param _collateralIndex index of collateral
     * @param _collateralValue collateral value (collateral precision)
     */
    function getUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _collateralValue
    ) external view returns (uint256);

    /**
     * @dev Returns collateral value (collateral precision) from USD normalized value
     * @param _collateralIndex index of collateral
     * @param _normalizedValue normalized value (1e18 USD)
     */
    function getCollateralFromUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _normalizedValue
    ) external view returns (uint256);

    /**
     * @dev Returns RewardsToken/USD price
     */
    function getRewardsTokenPriceUsd() external view returns (uint256);

    /**
     * @dev Emitted when collateral/USD price feed is updated
     * @param collateralIndex collateral index
     * @param value new value
     */
    event CollateralUsdPriceFeedUpdated(uint8 collateralIndex, bytes32 value);

    error WrongCollateralUsdDecimals();
}
