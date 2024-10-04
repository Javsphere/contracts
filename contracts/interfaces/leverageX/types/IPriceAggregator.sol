// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;


import "../../IJavPriceAggregator.sol";
import "./ITradingStorage.sol";

/**
 * @custom:version 8
 * @dev Contains the types for the JavPriceAggregator facet
 */




interface IPriceAggregator {
    struct PriceAggregatorStorage {
        // slot 1
        IJavPriceAggregator oracle;
        IJavPriceAggregator alternativeOracle;
        mapping(uint8 => bytes32) collateralUsdPriceFeed;
        bytes32 rewardsTokenUsdFeed;
        uint96 __placeholder; // 96 bits
        uint256[41] __gap;
    }


}