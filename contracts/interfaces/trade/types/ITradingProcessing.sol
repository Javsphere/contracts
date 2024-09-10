// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @custom:version 8
 * @dev Contains the types for the JavTradingInteractions facet
 */
interface ITradingProcessing {

    enum CancelReason {
        NONE,
        MARKET_CLOSED,
        SLIPPAGE,
        TP_REACHED,
        SL_REACHED,
        EXPOSURE_LIMITS,
        PRICE_IMPACT,
        MAX_LEVERAGE,
        NO_TRADE,
        NOT_HIT
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint256 positionSizeCollateral;
        int256 profitP;
        uint256 executionPrice;
        uint256 liqPrice;
        uint256 amountSentToTrader;
        uint256 reward1;
        uint256 reward2;
        uint256 reward3;
        uint128 collateralPrecisionDelta;
        uint256 collateralPriceUsd;
        bool exactExecution;
        uint256 closingFeeCollateral;
        uint256 triggerFeeCollateral;
        uint256 collateralLeftInStorage;
    }

    struct TradingProcessingStorage {
        uint8 vaultClosingFeeP; // 8 bits
        uint80 __placeholder;
        mapping(uint8 => uint256) pendingGovFees; // collateralIndex => pending gov fee (collateral)
        uint256[47] __gap;
    }

}