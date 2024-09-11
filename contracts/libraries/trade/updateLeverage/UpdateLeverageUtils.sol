// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../../interfaces/trade/IJavMultiCollatDiamond.sol";

import "../TradingCommonUtils.sol";

/**
 *
 * @dev This is an external library for leverage update lifecycles
 * @dev Used by JavTrading and  facet
 */
library UpdateLeverageUtils {
    /**
     * @dev Initiate update leverage order, done in 2 steps because need to cancel if liquidation price reached
     * @param _input request decrease leverage input
     */
    function updateLeverage(IUpdateLeverageUtils.UpdateLeverageInput memory _input) external {
        // 1. Request validation
        (
            ITradingStorage.Trade memory trade,
            bool isIncrease,
            uint256 collateralDelta
        ) = _validateRequest(_input);

        // 2. If decrease leverage, transfer collateral delta to diamond
        if (!isIncrease)
            TradingCommonUtils.transferCollateralFrom(
                trade.collateralIndex,
                trade.user,
                collateralDelta
            );

        // 3. Refresh trader fee tier cache
        TradingCommonUtils.updateFeeTierPoints(
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            0
        );

        // 4. Prepare useful values
        IUpdateLeverageUtils.UpdateLeverageValues memory values = _prepareValues(
            trade,
            collateralDelta,
            _input.newLeverage,
            isIncrease
        );

        uint256 price = _getMultiCollatDiamond().getPrice(trade.pairIndex);

        if ((trade.long && price <= values.liqPrice) || (!trade.long && price >= values.liqPrice)) {
            revert IGeneralErrors.LiqReached();
        }

        // 5.1 Distribute gov fee
        TradingCommonUtils.distributeExactGovFeeCollateral(
            trade.collateralIndex,
            trade.user,
            values.govFeeCollateral // use min fee / 2
        );

        // 5.2 Handle callback (update trade in storage, remove gov fee OI, handle collateral delta transfers)
        _handleUpdate(trade, values, collateralDelta, isIncrease);

        emit IUpdateLeverageUtils.LeverageUpdateExecuted(
            ITradingStorage.Id({user: _input.user, index: _input.index}),
            isIncrease,
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            trade.index,
            price,
            collateralDelta,
            values
        );
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }

    /**
     * @dev Returns new trade collateral amount based on new leverage (collateral precision)
     * @param _existingCollateralAmount existing trade collateral amount (collateral precision)
     * @param _existingLeverage existing trade leverage (1e3)
     * @param _newLeverage new trade leverage (1e3)
     */
    function _getNewCollateralAmount(
        uint256 _existingCollateralAmount,
        uint256 _existingLeverage,
        uint256 _newLeverage
    ) internal pure returns (uint120) {
        return uint120((_existingCollateralAmount * _existingLeverage) / _newLeverage);
    }

    /**
     * @dev Fetches trade, does validation for update leverage request, and returns useful data
     * @param _input request input struct
     */
    function _validateRequest(
        IUpdateLeverageUtils.UpdateLeverageInput memory _input
    )
        internal
        view
        returns (ITradingStorage.Trade memory trade, bool isIncrease, uint256 collateralDelta)
    {
        trade = _getMultiCollatDiamond().getTrade(_input.user, _input.index);
        isIncrease = _input.newLeverage > trade.leverage;

        // 1. Check trade exists
        if (!trade.isOpen) revert IGeneralErrors.DoesntExist();

        // 2. Revert if collateral not active
        if (!_getMultiCollatDiamond().isCollateralActive(trade.collateralIndex))
            revert IGeneralErrors.InvalidCollateralIndex();

        // 3. Validate leverage update
        if (
            _input.newLeverage == trade.leverage ||
            (
                isIncrease
                    ? _input.newLeverage >
                        _getMultiCollatDiamond().pairMaxLeverage(trade.pairIndex) * 1e3
                    : _input.newLeverage <
                        _getMultiCollatDiamond().pairMinLeverage(trade.pairIndex) * 1e3
            )
        ) revert ITradingInteractionsUtils.WrongLeverage();

        // 4. Check trade remaining collateral is enough to pay gov fee
        uint256 govFeeCollateral = TradingCommonUtils.getGovFeeCollateral(
            trade.user,
            trade.pairIndex,
            TradingCommonUtils.getMinPositionSizeCollateral(
                trade.collateralIndex,
                trade.pairIndex
            ) / 2
        );
        uint256 newCollateralAmount = _getNewCollateralAmount(
            trade.collateralAmount,
            trade.leverage,
            _input.newLeverage
        );
        collateralDelta = isIncrease
            ? trade.collateralAmount - newCollateralAmount
            : newCollateralAmount - trade.collateralAmount;

        if (newCollateralAmount <= govFeeCollateral)
            revert ITradingInteractionsUtils.InsufficientCollateral();
    }

    /**
     * @dev Calculates values for callback
     * @param _trade existing trade struct
     * @param _collateralDelta collateral amount delta
     * @param _newLeverage new leverage number
     * @param _isIncrease true if increase leverage, false if decrease leverage
     */
    function _prepareValues(
        ITradingStorage.Trade memory _trade,
        uint256 _collateralDelta,
        uint24 _newLeverage,
        bool _isIncrease
    ) internal view returns (IUpdateLeverageUtils.UpdateLeverageValues memory values) {
        if (_trade.isOpen == false) return values;

        values.newLeverage = _newLeverage;
        values.govFeeCollateral = TradingCommonUtils.getGovFeeCollateral(
            _trade.user,
            _trade.pairIndex,
            TradingCommonUtils.getMinPositionSizeCollateral(
                _trade.collateralIndex,
                _trade.pairIndex
            ) / 2 // use min fee / 2
        );
        values.newCollateralAmount =
            (
                _isIncrease
                    ? _trade.collateralAmount - _collateralDelta
                    : _trade.collateralAmount + _collateralDelta
            ) -
            values.govFeeCollateral;
        values.liqPrice = _getMultiCollatDiamond().getTradeLiquidationPrice(
            IBorrowingFees.LiqPriceInput(
                _trade.collateralIndex,
                _trade.user,
                _trade.pairIndex,
                _trade.index,
                _trade.openPrice,
                _trade.long,
                _isIncrease ? values.newCollateralAmount : _trade.collateralAmount,
                _isIncrease ? values.newLeverage : _trade.leverage,
                true,
                _getMultiCollatDiamond().getTradeLiquidationParams(_trade.user, _trade.index)
            )
        ); // for increase leverage we calculate new trade liquidation price and for decrease leverage we calculate existing trade liquidation price
    }

    /**
     * @dev Handles trade update, removes gov fee OI, and transfers collateral delta (for both successful and failed requests)
     * @param _trade trade struct
     * @param _values pre-calculated useful values
     * @param _isIncrease true if increase leverage, false if decrease leverage
     */
    function _handleUpdate(
        ITradingStorage.Trade memory _trade,
        IUpdateLeverageUtils.UpdateLeverageValues memory _values,
        uint256 _collateralDelta,
        bool _isIncrease
    ) internal {
        // 1. Request successful
        // 1.1 Update trade collateral (- gov fee) and leverage, openPrice stays the same
        _getMultiCollatDiamond().updateTradePosition(
            ITradingStorage.Id(_trade.user, _trade.index),
            uint120(_values.newCollateralAmount),
            uint24(_values.newLeverage),
            _trade.openPrice,
            false
        );

        // 1.2 If leverage increase, transfer collateral delta to trader
        if (_isIncrease)
            TradingCommonUtils.transferCollateralTo(
                _trade.collateralIndex,
                _trade.user,
                _collateralDelta
            );
    }
}
