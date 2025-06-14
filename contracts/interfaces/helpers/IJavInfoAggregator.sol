// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IJavInfoAggregator {
    function getTotalJavAmount(address _holder) external view returns (uint256);
    function getJavFreezerAmount(address _holder) external view returns (uint256);
    function getJavPrice(uint8 _targetDecimals) external view returns (uint256);

    event SetPriceFeed(address indexed token, bytes32 feedId);

    event SetJavlisAddress(address indexed _address);
    event SetJavlisVirtualPool(address indexed _address);
    event SetEthAddress(address indexed _address);
    event SetVirtualEthPool(address indexed _address);

    error ZeroAddress();
}
