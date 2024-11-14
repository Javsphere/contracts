// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
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

    EnumerableSet.AddressSet private _allowedSigners;
    mapping(bytes32 => IJavPriceAggregator.Price) private _latestPriceInfo;

    uint256 public priceUpdateFee;
    uint256 public updatePriceLifetime;

    /* ========== EVENTS ========== */
    event AddAllowedSigner(address indexed _address);
    event RemoveAllowedSigner(address indexed _address);
    event SetPriceUpdateFee(uint256 indexed _priceUpdateFee);
    event UpdatePriceFeed(bytes32 indexed id, int64 price, uint64 publishTime);
    event ClaimFee(address indexed to, uint256 amount);
    event SetUpdatePriceLifetime(uint256 indexed lifetime);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _priceUpdateFee,
        address[] memory _allowedSigners_
    ) external initializer {
        priceUpdateFee = _priceUpdateFee;

        for (uint256 i = 0; i < _allowedSigners_.length; i++) {
            _allowedSigners.add(_allowedSigners_[i]);
        }

        __Base_init();
    }

    function addAllowedSigner(address _address) external onlyAdmin {
        _allowedSigners.add(_address);

        emit AddAllowedSigner(_address);
    }

    function removeAllowedSigner(address _address) external onlyAdmin {
        _allowedSigners.remove(_address);

        emit RemoveAllowedSigner(_address);
    }

    function setPriceUpdateFee(uint256 _priceUpdateFee) external onlyAdmin {
        priceUpdateFee = _priceUpdateFee;

        emit SetPriceUpdateFee(_priceUpdateFee);
    }

    function setUpdatePriceLifetime(uint256 _lifetime) external onlyAdmin {
        updatePriceLifetime = _lifetime;

        emit SetUpdatePriceLifetime(_lifetime);
    }

    /**
     * @notice Function to get all allowed addresses
     */
    function getAllowedSigners() external view returns (address[] memory) {
        return _allowedSigners.values();
    }

    function getUpdateFee(bytes[] calldata updateData) external view returns (uint) {
        return updateData.length * priceUpdateFee;
    }

    function getPrice(bytes32 id) external view returns (IJavPriceAggregator.Price memory price) {
        return _latestPriceInfo[id];
    }

    function getPriceUnsafe(
        bytes32 id
    ) external view returns (IJavPriceAggregator.Price memory price) {
        return _latestPriceInfo[id];
    }

    function getPriceNoOlderThan(
        bytes32 id,
        uint age
    ) external view returns (IJavPriceAggregator.Price memory price) {
        price = _latestPriceInfo[id];

        require(_diff(block.timestamp, price.publishTime) > age, StalePrice());

        return price;
    }

    function updatePriceFeeds(bytes[] calldata updateData) external payable {
        for (uint256 i = 0; i < updateData.length; i++) {
            bytes memory data = updateData[i];
            require(data.length >= 65, "JavPriceAggregator: invalid data length"); // 65 bytes for the signature

            // Extract the signature (first 65 bytes)
            bytes memory signature = _slice(data, 0, 65);

            // Extract the UpdatePriceInfo struct (remaining bytes)
            bytes memory encodedData = _slice(data, 65, data.length - 65);

            // Verify the signature
            address signer = _recover(keccak256(encodedData), signature);
            require(_allowedSigners.contains(signer), "JavPriceAggregator: Invalid signature");

            UpdatePriceInfo memory _priceInfo = abi.decode(encodedData, (UpdatePriceInfo));
            require(_priceInfo.publishTime >= block.timestamp - updatePriceLifetime, StalePrice());
            _latestPriceInfo[_priceInfo.id] = IJavPriceAggregator.Price({
                price: _priceInfo.price,
                conf: _priceInfo.conf,
                expo: _priceInfo.expo,
                publishTime: _priceInfo.publishTime
            });
            emit UpdatePriceFeed(_priceInfo.id, _priceInfo.price, _priceInfo.publishTime);
        }
    }

    function claimFee(address payable _to) external onlyAdmin {
        uint256 _amount = address(this).balance;
        _to.transfer(_amount);

        emit ClaimFee(_to, _amount);
    }

    function _diff(uint x, uint y) private pure returns (uint) {
        if (x > y) {
            return x - y;
        } else {
            return y - x;
        }
    }

    function _slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) private pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    function _recover(bytes32 messageHash, bytes memory signature) private pure returns (address) {
        return ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
    }
}
