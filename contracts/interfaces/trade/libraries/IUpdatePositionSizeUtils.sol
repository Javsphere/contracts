// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/IUpdatePositionSize.sol";
import "../types/ITradingStorage.sol";
import "../types/ITradingProcessing.sol";

/**
 * @dev Interface for position size updates
 */
interface IUpdatePositionSizeUtils is IUpdatePositionSize {
    /**
     * @param orderId request order id
     * @param collateralIndex collateral index
     * @param trader address of trader
     * @param pairIndex index of pair
     * @param index index of trade
     * @param marketPrice market price (1e10)
     * @param collateralDelta collateral delta (collateral precision)
     * @param leverageDelta leverage delta (1e3)
     * @param values important values (new open price, new leverage, new collateral, etc.)
     */
    event PositionSizeIncreaseExecuted(
        ITradingStorage.Id orderId,
        uint8 indexed collateralIndex,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 marketPrice,
        uint256 collateralDelta,
        uint256 leverageDelta,
        IUpdatePositionSize.IncreasePositionSizeValues values
    );

    /**
     * @param orderId request order id
     * @param collateralIndex collateral index
     * @param trader address of trader
     * @param pairIndex index of pair
     * @param index index of trade
     * @param marketPrice market price (1e10)
     * @param collateralDelta collateral delta (collateral precision)
     * @param leverageDelta leverage delta (1e3)
     * @param values important values (pnl, new leverage, new collateral, etc.)
     */
    event PositionSizeDecreaseExecuted(
        ITradingStorage.Id orderId,
        uint8 indexed collateralIndex,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 marketPrice,
        uint256 collateralDelta,
        uint256 leverageDelta,
        IUpdatePositionSize.DecreasePositionSizeValues values
    );

    error InvalidIncreasePositionSizeInput();
    error InvalidDecreasePositionSizeInput();
    error NewPositionSizeSmaller();
}
