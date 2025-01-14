// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @custom:version 8
 *
 * @dev Internal library to manage storage slots of JavMultiCollatDiamond contract diamond storage structs.
 *
 * BE EXTREMELY CAREFUL, DO NOT EDIT THIS WITHOUT A GOOD REASON
 *
 */
library StorageUtils {
    uint256 internal constant GLOBAL_ADDRESSES_SLOT = 52;
    uint256 internal constant GLOBAL_PAIRS_STORAGE_SLOT = 102;
    uint256 internal constant GLOBAL_REFERRALS_SLOT = 152;
    uint256 internal constant GLOBAL_FEE_TIERS_SLOT = 202;
    uint256 internal constant GLOBAL_PRICE_IMPACT_SLOT = 252;
    uint256 internal constant GLOBAL_DIAMOND_SLOT = 302;
    uint256 internal constant GLOBAL_TRADING_STORAGE_SLOT = 352;
    uint256 internal constant GLOBAL_TRADING_SLOT = 400;
    uint256 internal constant GLOBAL_TRADING_CLOSE_SLOT = 448;
    uint256 internal constant GLOBAL_BORROWING_FEES_SLOT = 497;
    uint256 internal constant GLOBAL_PRICE_AGGREGATOR_SLOT = 547;
}
