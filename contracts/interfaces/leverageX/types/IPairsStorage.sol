// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @custom:version 8
 * @dev Contains the types for the JavPairsStorage facet
 */
interface IPairsStorage {
    struct PairsStorage {
        mapping(uint256 => Pair) pairs;
        mapping(uint256 => Group) groups;
        mapping(uint256 => Fee) fees;
        mapping(string => mapping(string => bool)) isPairListed;
        mapping(uint256 => uint256) pairCustomMaxLeverage; // 0 decimal precision
        uint256 pairsCount;
        uint256 groupsCount;
        uint256 feesCount;
        mapping(uint256 => GroupLiquidationParams) groupLiquidationParams;
        mapping(uint256 => bool) isPairRemoved;
        uint256[40] __gap;
    }


    struct Pair {
        string from;
        string to;
        bytes32 feedId;
        uint256 spreadP; // 1e10
        uint256 groupIndex;
        uint256 feeIndex;
        bool altPriceOracle;
    }

    struct Group {
        string name;
        uint256 minLeverage; // 0 decimal precision
        uint256 maxLeverage; // 0 decimal precision
    }
    struct Fee {
        string name;
        uint256 openFeeP; // PRECISION (% of position size)
        uint256 closeFeeP; // PRECISION (% of position size)
        uint256 triggerOrderFeeP; // PRECISION (% of position size)
        uint256 minPositionSizeUsd; // 1e18 (collateral x leverage, useful for min fee)
    }

    struct GroupLiquidationParams {
        uint40 maxLiqSpreadP; // 1e10 (%)
        uint40 startLiqThresholdP; // 1e10 (%)
        uint40 endLiqThresholdP; // 1e10 (%)
        uint24 startLeverage; // 1e3
        uint24 endLeverage; // 1e3
    }
}