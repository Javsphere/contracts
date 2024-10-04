// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./IJavDiamond.sol";
import "./libraries/IPairsStorageUtils.sol";
import "./libraries/IReferralsUtils.sol";
import "./libraries/IFeeTiersUtils.sol";
import "./libraries/IPriceImpactUtils.sol";
import "./libraries/ITradingStorageUtils.sol";
import "./libraries/ITradingInteractionsUtils.sol";
import "./libraries/ITradingProcessingUtils.sol";
import "./libraries/IBorrowingFeesUtils.sol";
import "./libraries/IPriceAggregatorUtils.sol";
import "../libraries/IPriceUtils.sol";

/**
 * @custom:version 8
 * @dev Expanded version of multi-collat diamond that includes events and function signatures
 * Technically this interface is virtual since the diamond doesn't directly implement these functions.
 * It only forwards the calls to the facet contracts using delegatecall.
 */
interface IJavMultiCollatDiamond is
    IJavDiamond,
    IPairsStorageUtils,
    IReferralsUtils,
    IFeeTiersUtils,
    IPriceImpactUtils,
    ITradingStorageUtils,
    ITradingInteractionsUtils,
    ITradingProcessingUtils,
    IBorrowingFeesUtils,
    IPriceAggregatorUtils,
    IPriceUtils
{

}
