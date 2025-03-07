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
        mapping(uint256 => Fee) fees; /// @custom:deprecated
        mapping(string => mapping(string => bool)) isPairListed;
        mapping(uint256 => uint256) pairCustomMaxLeverage; // 0 decimal precision
        uint256 pairsCount;
        uint256 groupsCount;
        uint256 feesCount;
        mapping(uint256 => GroupLiquidationParams) groupLiquidationParams;
        mapping(uint256 => bool) isPairRemoved;
        mapping(uint256 => FeeGroup) feeGroups;
        GlobalTradeFeeParams globalTradeFeeParams;
        uint256[38] __gap;
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
        uint256 minLeverage; // 1e3 precision
        uint256 maxLeverage; // 1e3 precision
    }
    struct Fee {
        string name;
        uint256 openFeeP; // PRECISION (% of position size)
        uint256 closeFeeP; // PRECISION (% of position size)
        uint256 triggerOrderFeeP; // PRECISION (% of position size)
        uint256 minPositionSizeUsd; // 1e18 (collateral x leverage, useful for min fee)
    }

    struct GlobalTradeFeeParams {
        uint24 referralFeeP; // 1e3 (%)
        uint24 govFeeP; // 1e3 (%)
        uint24 llpTokenFeeP; // 1e3 (%)
        uint24 triggerOrderFeeP; // 1e3 (%)
        uint112 __placeholder;
    }

    struct FeeGroup {
        uint40 totalPositionSizeFeeP; // 1e10 (%)
        uint40 totalLiqCollateralFeeP; // 1e10 (%)
        uint32 minPositionSizeUsd; // 1e3
        uint104 __placeholder;
    }

    struct TradeFees {
        uint256 totalFeeCollateral; // collateral precision
        uint256 referralFeeCollateral; // collateral precision
        uint256 govFeeCollateral; // collateral precision
        uint256 llpTokenFeeCollateral; // collateral precision
        uint256 triggerOrderFeeCollateral; // collateral precision
    }

    struct GroupLiquidationParams {
        uint40 maxLiqSpreadP; // 1e10 (%)
        uint40 startLiqThresholdP; // 1e10 (%)
        uint40 endLiqThresholdP; // 1e10 (%)
        uint24 startLeverage; // 1e3
        uint24 endLeverage; // 1e3
    }
}