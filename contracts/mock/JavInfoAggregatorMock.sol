// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../interfaces/helpers/IJavInfoAggregator.sol";
import "hardhat/console.sol";

contract JavInfoAggregatorMock is IJavInfoAggregator {
    function getTotalJavAmount(address _holder) external view returns (uint256) {
        return 1000 * 1e18;
    }
    function getJavFreezerAmount(address _holder) external view returns (uint256) {
        return 1000 * 1e18;
    }

    function getJavPrice(uint8 _targetDecimals) external view returns (uint256) {
        uint256 precision = 10 ** _targetDecimals;
        return 1 * precision;
    }
}
