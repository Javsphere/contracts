// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @custom:version 8
 * @dev Contains the types for the JavPriceImpact facet
 */
interface IPriceImpact {
    struct PriceImpactStorage {
        OiWindowsSettings oiWindowsSettings;
        mapping(uint48 => mapping(uint256 => mapping(uint256 => PairOi))) windows; // duration => pairIndex => windowId => Oi
        mapping(uint256 => PairDepth) pairDepths; // pairIndex => depth (USD)
        mapping(address => mapping(uint32 => TradePriceImpactInfo)) tradePriceImpactInfos;
        uint256[46] __gap;
    }

    struct OiWindowsSettings {
        uint48 startTs;
        uint48 windowsDuration;
        uint48 windowsCount;
    }

    struct PairOi {
        uint128 oiLongUsd; // 1e18 USD
        uint128 oiShortUsd; // 1e18 USD
    }

    struct OiWindowUpdate {
        address trader;
        uint32 index;
        uint48 windowsDuration;
        uint256 pairIndex;
        uint256 windowId;
        bool long;
        uint128 openInterestUsd; // 1e18 USD
    }

    struct PairDepth {
        uint128 onePercentDepthAboveUsd; // USD
        uint128 onePercentDepthBelowUsd; // USD
    }

    struct TradePriceImpactInfo {
        uint128 lastWindowOiUsd; // 1e18 USD
        uint128 __placeholder;
    }
}