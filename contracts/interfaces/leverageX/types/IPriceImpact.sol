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
        mapping(uint256 => PairFactors) pairFactors;
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
        bool open;
        uint128 openInterestUsd; // 1e18 USD
    }

    struct PairDepth {
        uint128 onePercentDepthAboveUsd; // USD
        uint128 onePercentDepthBelowUsd; // USD
    }

    struct PairFactors {
        uint40 protectionCloseFactor; // 1e10; max 109.95x
        uint32 protectionCloseFactorBlocks;
        uint40 cumulativeFactor; // 1e10; max 109.95x
        uint144 __placeholder;
    }


}