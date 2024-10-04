// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./IDiamondStorage.sol";
import "./IPairsStorage.sol";
import "./IReferrals.sol";
import "./IFeeTiers.sol";
import "./IPriceImpact.sol";
import "./ITradingStorage.sol";
import "./ITradingInteractions.sol";
import "./ITradingProcessing.sol";
import "./IBorrowingFees.sol";
import "./IPriceAggregator.sol";

/**
 * @dev Contains the types of all diamond facets
 */
interface ITypes is
IDiamondStorage,
IPairsStorage,
IReferrals,
IFeeTiers,
IPriceImpact,
ITradingStorage,
ITradingInteractions,
ITradingProcessing,
IBorrowingFees,
IPriceAggregator
{

}