// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/IPriceAggregatorUtils.sol";
import "../libraries/trade/PriceAggregatorUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #10: Price aggregator (does the requests to the Chainlink DON, takes the median, and executes callbacks)
 */
contract GNSPriceAggregator is JavAddressStore, IPriceAggregatorUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function initializePriceAggregator(
        address _linkToken,
        IChainlinkFeed _linkUsdPriceFeed,
        uint24 _twapInterval,
        uint8 _minAnswers,
        address[] memory _nodes,
        bytes32[2] memory _jobIds,
        uint8[] calldata _collateralIndices,
        IUniswapV3Pool[] memory _gnsCollateralUniV3Pools,
        IChainlinkFeed[] memory _collateralUsdPriceFeeds
    ) external reinitializer(11) {
        PriceAggregatorUtils.initializePriceAggregator(
            _linkToken,
            _linkUsdPriceFeed,
            _twapInterval,
            _minAnswers,
            _nodes,
            _jobIds,
            _collateralIndices,
            _gnsCollateralUniV3Pools,
            _collateralUsdPriceFeeds
        );
    }

    // Management Setters

    /// @inheritdoc IPriceAggregatorUtils
    function updateLinkUsdPriceFeed(IChainlinkFeed _value) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.updateLinkUsdPriceFeed(_value);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function updateCollateralUsdPriceFeed(
        uint8 _collateralIndex,
        IChainlinkFeed _value
    ) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.updateCollateralUsdPriceFeed(_collateralIndex, _value);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function updateCollateralGnsUniV3Pool(
        uint8 _collateralIndex,
        IUniswapV3Pool _uniV3Pool
    ) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.updateCollateralGnsUniV3Pool(_collateralIndex, _uniV3Pool);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function updateTwapInterval(uint24 _twapInterval) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.updateTwapInterval(_twapInterval);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function updateMinAnswers(uint8 _value) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.updateMinAnswers(_value);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function addOracle(address _a) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.addOracle(_a);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function replaceOracle(uint256 _index, address _a) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.replaceOracle(_index, _a);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function removeOracle(uint256 _index) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.removeOracle(_index);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function setMarketJobId(bytes32 _jobId) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.setMarketJobId(_jobId);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function setLimitJobId(bytes32 _jobId) external onlyRole(Role.GOV) {
        PriceAggregatorUtils.setLimitJobId(_jobId);
    }

    // Interactions

    /// @inheritdoc IPriceAggregatorUtils
    function getPrice(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        ITradingStorage.Id memory _orderId,
        ITradingStorage.PendingOrderType _orderType,
        uint256 _positionSizeCollateral,
        uint256 _fromBlock
    ) external virtual onlySelf {
        PriceAggregatorUtils.getPrice(
            _collateralIndex,
            _pairIndex,
            _orderId,
            _orderType,
            _positionSizeCollateral,
            _fromBlock
        );
    }

    /// @inheritdoc IPriceAggregatorUtils
    function fulfill(bytes32 _requestId, uint256 _priceData) external {
        PriceAggregatorUtils.fulfill(_requestId, _priceData); // access control handled by library (validates chainlink callback)
    }

    /// @inheritdoc IPriceAggregatorUtils
    function claimBackLink() external onlyRole(Role.GOV) {
        PriceAggregatorUtils.claimBackLink();
    }

    // Getters

    /// @inheritdoc IPriceAggregatorUtils
    function getLinkFee(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        uint256 _positionSizeCollateral
    ) external view returns (uint256) {
        return
            PriceAggregatorUtils.getLinkFee(_collateralIndex, _pairIndex, _positionSizeCollateral);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getCollateralPriceUsd(uint8 _collateralIndex) external view returns (uint256) {
        return PriceAggregatorUtils.getCollateralPriceUsd(_collateralIndex);
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
    function getGnsPriceUsd(uint8 _collateralIndex) external view virtual returns (uint256) {
        return PriceAggregatorUtils.getGnsPriceUsd(_collateralIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getGnsPriceUsd(
        uint8 _collateralIndex,
        uint256 _gnsPriceCollateral
    ) external view returns (uint256) {
        return PriceAggregatorUtils.getGnsPriceUsd(_collateralIndex, _gnsPriceCollateral);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getGnsPriceCollateralIndex(
        uint8 _collateralIndex
    ) external view virtual returns (uint256) {
        return PriceAggregatorUtils.getGnsPriceCollateralIndex(_collateralIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getGnsPriceCollateralAddress(
        address _collateral
    ) external view virtual returns (uint256) {
        return PriceAggregatorUtils.getGnsPriceCollateralAddress(_collateral);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getLinkUsdPriceFeed() external view returns (IChainlinkFeed) {
        return PriceAggregatorUtils.getLinkUsdPriceFeed();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getTwapInterval() external view returns (uint24) {
        return PriceAggregatorUtils.getTwapInterval();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getMinAnswers() external view returns (uint8) {
        return PriceAggregatorUtils.getMinAnswers();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getMarketJobId() external view returns (bytes32) {
        return PriceAggregatorUtils.getMarketJobId();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getLimitJobId() external view returns (bytes32) {
        return PriceAggregatorUtils.getLimitJobId();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getOracle(uint256 _index) external view returns (address) {
        return PriceAggregatorUtils.getOracle(_index);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getOracles() external view returns (address[] memory) {
        return PriceAggregatorUtils.getOracles();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getCollateralGnsUniV3Pool(
        uint8 _collateralIndex
    ) external view returns (UniV3PoolInfo memory) {
        return PriceAggregatorUtils.getCollateralGnsUniV3Pool(_collateralIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getCollateralUsdPriceFeed(
        uint8 _collateralIndex
    ) external view returns (IChainlinkFeed) {
        return PriceAggregatorUtils.getCollateralUsdPriceFeed(_collateralIndex);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getPriceAggregatorOrder(bytes32 _requestId) external view returns (Order memory) {
        return PriceAggregatorUtils.getPriceAggregatorOrder(_requestId);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getPriceAggregatorOrderAnswers(
        ITradingStorage.Id calldata _orderId
    ) external view returns (OrderAnswer[] memory) {
        return PriceAggregatorUtils.getPriceAggregatorOrderAnswers(_orderId);
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getChainlinkToken() external view returns (address) {
        return PriceAggregatorUtils.getChainlinkToken();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getRequestCount() external view returns (uint256) {
        return PriceAggregatorUtils.getRequestCount();
    }

    /// @inheritdoc IPriceAggregatorUtils
    function getPendingRequest(bytes32 _id) external view returns (address) {
        return PriceAggregatorUtils.getPendingRequest(_id);
    }
}
