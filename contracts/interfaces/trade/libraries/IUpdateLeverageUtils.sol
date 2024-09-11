// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/IUpdateLeverage.sol";
import "../types/ITradingStorage.sol";
import "../types/ITradingProcessing.sol";

/**
 * @dev Interface for leverage updates
 */
interface IUpdateLeverageUtils is IUpdateLeverage {
    /**
     * @param orderId request order id
     * @param isIncrease true if leverage increased, false if decreased
     * @param collateralIndex collateral index
     * @param trader address of trader
     * @param pairIndex index of pair
     * @param index index of trade
     * @param marketPrice current market price (1e10)
     * @param collateralDelta collateral delta (collateral precision)
     * @param values useful values (new collateral, new leverage, liq price, gov fee collateral)
     */
    event LeverageUpdateExecuted(
        ITradingStorage.Id orderId,
        bool isIncrease,
        uint8 indexed collateralIndex,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 marketPrice,
        uint256 collateralDelta,
        IUpdateLeverage.UpdateLeverageValues values
    );
}
