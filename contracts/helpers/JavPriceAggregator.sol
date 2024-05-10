// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IJavPriceAggregator.sol";
import "../base/BaseUpgradable.sol";

contract JavPriceAggregator is IJavPriceAggregator, BaseUpgradable {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UpdatePriceInfo {
        // id
        bytes32 id;
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint64 publishTime;
    }

    EnumerableSet.AddressSet private _allowedAddresses;

    mapping(bytes32 => IJavPriceAggregator.Price) private _latestPriceInfo;

    /* ========== EVENTS ========== */
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
    event UpdatePriceFeed(bytes32 indexed id, int64 price, uint64 publishTime);

    modifier onlyAllowedAddresses() {
        require(
            _allowedAddresses.contains(msg.sender),
            "JavPriceAggregator: only allowed addresses"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory _allowedAddresses_) external initializer {
        for (uint256 i = 0; i < _allowedAddresses_.length; i++) {
            _allowedAddresses.add(_allowedAddresses_[i]);
        }

        __Base_init();
    }

    function addAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.add(_address);

        emit AddAllowedAddress(_address);
    }

    function removeAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.remove(_address);

        emit RemoveAllowedAddress(_address);
    }

    /**
     * @notice Function to get all allowed addresses
     */
    function getAllowedAddresses() external view returns (address[] memory) {
        return _allowedAddresses.values();
    }

    function getPrice(bytes32 id) external view returns (IJavPriceAggregator.Price memory price) {
        return _latestPriceInfo[id];
    }

    function updatePriceFeeds(UpdatePriceInfo[] memory _priceInfo) external onlyAllowedAddresses {
        for (uint256 i = 0; i < _priceInfo.length; i++) {
            _latestPriceInfo[_priceInfo[i].id] = IJavPriceAggregator.Price({
                price: _priceInfo[i].price,
                conf: _priceInfo[i].conf,
                expo: _priceInfo[i].expo,
                publishTime: _priceInfo[i].publishTime
            });
            emit UpdatePriceFeed(_priceInfo[i].id, _priceInfo[i].price, _priceInfo[i].publishTime);
        }
    }
}
