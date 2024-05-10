// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IJavPriceAggregator {
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint64 publishTime;
    }

    function getPrice(bytes32 id) external view returns (Price memory price);
}
