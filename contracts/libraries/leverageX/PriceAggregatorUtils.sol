// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/leverageX/IJavMultiCollatDiamond.sol";
import "../../interfaces/IJavPriceAggregator.sol";

import "./AddressStoreUtils.sol";
import "./StorageUtils.sol";
import "./PackingUtils.sol";
import "../PriceUtils.sol";

/**
 * @custom:version 8
 * @dev JavPriceAggregator facet internal library
 */
library PriceAggregatorUtils {
    using PackingUtils for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Reverts if collateral index is not valid
     */
    modifier validCollateralIndex(uint8 _collateralIndex) {
        if (!_getMultiCollatDiamond().isCollateralListed(_collateralIndex)) {
            revert IGeneralErrors.InvalidCollateralIndex();
        }
        _;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function initializePriceAggregator(
        IJavPriceAggregator _oracle,
        IJavPriceAggregator _alternativeOracle,
        bytes32 _rewardsTokenUsdFeed,
        uint8[] calldata _collateralIndices,
        bytes32[] memory _collateralUsdPriceFeeds
    ) internal {
        if (_collateralIndices.length != _collateralUsdPriceFeeds.length)
            revert IGeneralErrors.WrongLength();

        _getStorage().oracle = _oracle;
        _getStorage().alternativeOracle = _alternativeOracle;
        _getStorage().rewardsTokenUsdFeed = _rewardsTokenUsdFeed;

        for (uint8 i = 0; i < _collateralIndices.length; ++i) {
            updateCollateralUsdPriceFeed(_collateralIndices[i], _collateralUsdPriceFeeds[i]);
        }
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updateCollateralUsdPriceFeed(
        uint8 _collateralIndex,
        bytes32 _value
    ) internal validCollateralIndex(_collateralIndex) {
        if (_value == bytes32(0)) revert IGeneralErrors.ZeroValue();

        _getStorage().collateralUsdPriceFeed[_collateralIndex] = _value;

        emit IPriceAggregatorUtils.CollateralUsdPriceFeedUpdated(_collateralIndex, _value);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getPrice(uint16 _pairIndex) internal view returns (uint256) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        IPairsStorage.Pair memory pair = _getMultiCollatDiamond().pairs(_pairIndex);
        IJavPriceAggregator oracle = pair.altPriceOracle ? s.alternativeOracle : s.oracle;
        IJavPriceAggregator.Price memory price = oracle.getPrice(pair.feedId);
        return PriceUtils.convertToUint(price.price, price.expo, 10);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updatePrices(bytes[][] calldata _priceUpdate, address _user) internal {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        uint256 _totalFee;
        bytes[] memory _pythUpdateData = _priceUpdate[0];
        bytes[] memory _javUpdateData = _priceUpdate[1];
        if (_pythUpdateData.length > 0) {
            IJavPriceAggregator oracle = s.oracle;
            uint fee = oracle.getUpdateFee(_pythUpdateData);
            require(msg.value >= fee, "JavPriceAggregator: Invalid fee amount");
            oracle.updatePriceFeeds{value: fee}(_pythUpdateData);
            _totalFee += fee;
        }
        if (_javUpdateData.length > 0) {
            IJavPriceAggregator oracle = s.alternativeOracle;
            uint fee = oracle.getUpdateFee(_javUpdateData);
            require(msg.value - _totalFee >= fee, "JavPriceAggregator: Invalid fee amount");
            oracle.updatePriceFeeds{value: fee}(_javUpdateData);
            _totalFee += fee;
        }
        //  send unused eth back to user
        if (msg.value > _totalFee) {
            payable(_user).transfer(msg.value - _totalFee);
        }
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralPriceUsd(uint8 _collateralIndex) internal view returns (uint256) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        IJavPriceAggregator.Price memory price = s.oracle.getPriceUnsafe(
            s.collateralUsdPriceFeed[_collateralIndex]
        );
        return PriceUtils.convertToUint(price.price, price.expo, 8);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralFeed(uint8 _collateralIndex) internal view returns (bytes32) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        return s.collateralUsdPriceFeed[_collateralIndex];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getRewardsTokenUsdFeed() internal view returns (bytes32) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        return s.rewardsTokenUsdFeed;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _collateralValue
    ) internal view returns (uint256) {
        return
            (_collateralValue *
                _getCollateralPrecisionDelta(_collateralIndex) *
                getCollateralPriceUsd(_collateralIndex)) / 1e8;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralFromUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _normalizedValue
    ) internal view returns (uint256) {
        return
            (_normalizedValue * 1e8) /
            getCollateralPriceUsd(_collateralIndex) /
            _getCollateralPrecisionDelta(_collateralIndex);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getRewardsTokenPriceUsd() internal view returns (uint256) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        IJavPriceAggregator.Price memory price = s.oracle.getPrice(s.rewardsTokenUsdFeed);
        return PriceUtils.convertToUint(price.price, price.expo, 8);
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_PRICE_AGGREGATOR_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (IPriceAggregator.PriceAggregatorStorage storage s)
    {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }

    /**
     * @dev Returns precision delta of collateral as uint256
     * @param _collateralIndex index of collateral
     */
    function _getCollateralPrecisionDelta(uint8 _collateralIndex) internal view returns (uint256) {
        return uint256(_getMultiCollatDiamond().getCollateral(_collateralIndex).precisionDelta);
    }
}
