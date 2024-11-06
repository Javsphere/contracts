// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../../interfaces/leverageX/IJavMultiCollatDiamond.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../ConstantsUtils.sol";
import "../TradingCommonUtils.sol";

/**
 *
 * @dev This is an internal utils library for position size increases
 * @dev Used by UpdatePositionSizeLifecycles internal library
 */
library IncreasePositionSizeUtils {
    /**
     * @dev Validates increase position request.
     *
     * @dev Possible inputs: collateral delta > 0 and leverage delta > 0 (increase position size by collateral delta * leverage delta)
     *                       collateral delta = 0 and leverage delta > 0 (increase trade leverage by leverage delta)
     *
     * @param _trade trade of request
     * @param _input input values
     */
    function validateRequest(
        ITradingStorage.Trade memory _trade,
        IUpdatePositionSizeUtils.IncreasePositionSizeInput memory _input
    ) internal view {
        // 1. Zero values checks
        if (_input.leverageDelta == 0 || _input.expectedPrice == 0 || _input.maxSlippageP == 0)
            revert IUpdatePositionSizeUtils.InvalidIncreasePositionSizeInput();

        // 2. Revert if new leverage is below min leverage or above max leverage
        bool isLeverageUpdate = _input.collateralDelta == 0;
        {
            uint24 leverageToValidate = isLeverageUpdate
                ? _trade.leverage + _input.leverageDelta
                : _input.leverageDelta;
            if (
                leverageToValidate >
                _getMultiCollatDiamond().pairMaxLeverage(_trade.pairIndex) * 1e3 ||
                leverageToValidate <
                _getMultiCollatDiamond().pairMinLeverage(_trade.pairIndex) * 1e3
            ) revert ITradingInteractionsUtils.WrongLeverage();
        }

        // 3. Make sure new position size is bigger than existing one after paying borrowing and opening fees
        uint256 positionSizeCollateralDelta = TradingCommonUtils.getPositionSizeCollateral(
            isLeverageUpdate ? _trade.collateralAmount : _input.collateralDelta,
            _input.leverageDelta
        );
        uint256 existingPositionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
            _trade.collateralAmount,
            _trade.leverage
        );
        uint256 newCollateralAmount = _trade.collateralAmount + _input.collateralDelta;
        uint256 newLeverage = isLeverageUpdate
            ? _trade.leverage + _input.leverageDelta
            : ((existingPositionSizeCollateral + positionSizeCollateralDelta) * 1e3) /
                newCollateralAmount;
        {
            uint256 borrowingFeeCollateral = TradingCommonUtils.getTradeBorrowingFeeCollateral(
                _trade
            );
            uint256 openingFeesCollateral = ((_getMultiCollatDiamond().pairOpenFeeP(
                _trade.pairIndex
            ) *
                2 +
                _getMultiCollatDiamond().pairTriggerOrderFeeP(_trade.pairIndex)) *
                TradingCommonUtils.getPositionSizeCollateralBasis(
                    _trade.collateralIndex,
                    _trade.pairIndex,
                    positionSizeCollateralDelta
                )) /
                ConstantsUtils.P_10 /
                100;

            uint256 newPositionSizeCollateral = existingPositionSizeCollateral +
                positionSizeCollateralDelta -
                ((borrowingFeeCollateral + openingFeesCollateral) * newLeverage) /
                1e3;

            if (newPositionSizeCollateral <= existingPositionSizeCollateral)
                revert IUpdatePositionSizeUtils.NewPositionSizeSmaller();
        }

        // 4. Make sure trade stays within exposure limits
        if (
            !TradingCommonUtils.isWithinExposureLimits(
                _trade.collateralIndex,
                _trade.pairIndex,
                _trade.long,
                positionSizeCollateralDelta
            )
        ) revert ITradingInteractionsUtils.AboveExposureLimits();
    }

    /**
     * @dev Calculates values for callback
     * @param _existingTrade existing trade data
     * @param _collateralAmount collateral amount delta
     * @param _leverage new leverage number
     * @param _price price
     */
    function prepareValues(
        ITradingStorage.Trade memory _existingTrade,
        uint120 _collateralAmount,
        uint24 _leverage,
        uint64 _price
    ) internal view returns (IUpdatePositionSizeUtils.IncreasePositionSizeValues memory values) {
        bool isLeverageUpdate = _collateralAmount == 0;

        // 1. Calculate position size values
        values.positionSizeCollateralDelta = TradingCommonUtils.getPositionSizeCollateral(
            isLeverageUpdate ? _existingTrade.collateralAmount : _collateralAmount,
            _leverage
        );
        values.existingPositionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
            _existingTrade.collateralAmount,
            _existingTrade.leverage
        );
        values.newPositionSizeCollateral =
            values.existingPositionSizeCollateral +
            values.positionSizeCollateralDelta;

        // 2. Calculate new collateral amount and leverage
        values.newCollateralAmount = _existingTrade.collateralAmount + _collateralAmount;
        values.newLeverage = isLeverageUpdate
            ? _existingTrade.leverage + _leverage
            : (values.newPositionSizeCollateral * 1e3) / values.newCollateralAmount;

        // 3. Calculate price impact values
        // 3. Calculate price impact values
        (, values.priceAfterImpact) = TradingCommonUtils.getTradeOpeningPriceImpact(
            ITradingCommonUtils.TradePriceImpactInput(
                _existingTrade,
                _price,
                10,
                values.positionSizeCollateralDelta
            )
        );

        // 4. Calculate existing trade pnl
        values.existingPnlCollateral =
            (TradingCommonUtils.getPnlPercent(
                _existingTrade.openPrice,
                _price,
                _existingTrade.long,
                _existingTrade.leverage
            ) * int256(uint256(_existingTrade.collateralAmount))) /
            100 /
            int256(ConstantsUtils.P_10);

        // 5. Calculate existing trade borrowing fee
        values.borrowingFeeCollateral = TradingCommonUtils.getTradeBorrowingFeeCollateral(
            _existingTrade
        );

        // 6. Calculate partial trade opening fees

        // 6.1 Apply fee tiers
        uint256 pairOpenFeeP = _getMultiCollatDiamond().calculateFeeAmount(
            _existingTrade.user,
            _getMultiCollatDiamond().pairOpenFeeP(_existingTrade.pairIndex)
        );
        uint256 pairTriggerFeeP = _getMultiCollatDiamond().calculateFeeAmount(
            _existingTrade.user,
            _getMultiCollatDiamond().pairTriggerOrderFeeP(_existingTrade.pairIndex)
        );

        // 6.2 Calculate opening fees on on max(positionSizeCollateralDelta, minPositionSizeCollateral)
        values.openingFeesCollateral =
            ((pairOpenFeeP * 2 + pairTriggerFeeP) *
                TradingCommonUtils.getPositionSizeCollateralBasis(
                    _existingTrade.collateralIndex,
                    _existingTrade.pairIndex,
                    values.positionSizeCollateralDelta
                )) /
            100 /
            ConstantsUtils.P_10;

        // 7. Charge opening fees and borrowing fees on new trade collateral amount
        values.newCollateralAmount -= values.borrowingFeeCollateral + values.openingFeesCollateral;

        // 8. Calculate new open price

        // existingPositionSizeCollateral + existingPnlCollateral can never be negative
        // Because minimum value for existingPnlCollateral is -100% of trade collateral
        uint256 positionSizePlusPnlCollateral = values.existingPnlCollateral < 0
            ? values.existingPositionSizeCollateral - uint256(values.existingPnlCollateral * -1)
            : values.existingPositionSizeCollateral + uint256(values.existingPnlCollateral);

        values.newOpenPrice =
            (positionSizePlusPnlCollateral *
                uint256(_existingTrade.openPrice) +
                values.positionSizeCollateralDelta *
                values.priceAfterImpact) /
            (positionSizePlusPnlCollateral + values.positionSizeCollateralDelta);

        // 8. Calculate existing and new liq price
        values.existingLiqPrice = TradingCommonUtils.getTradeLiquidationPrice(_existingTrade, true);
        values.newLiqPrice = _getMultiCollatDiamond().getTradeLiquidationPrice(
            IBorrowingFees.LiqPriceInput(
                _existingTrade.collateralIndex,
                _existingTrade.user,
                _existingTrade.pairIndex,
                _existingTrade.index,
                uint64(values.newOpenPrice),
                _existingTrade.long,
                values.newCollateralAmount,
                values.newLeverage,
                false,
                _getMultiCollatDiamond().getPairLiquidationParams(_existingTrade.pairIndex) // new liquidation params
            )
        );
    }

    /**
     * @dev Validates callback, and returns corresponding cancel reason
     * @param _existingTrade existing trade data
     * @param _values pre-calculated useful values
     * @param _price price
     * @param _expectedPrice user expected price before callback (1e10)
     * @param _maxSlippageP maximum slippage percentage from expected price (1e3)
     */
    function validateValues(
        ITradingStorage.Trade memory _existingTrade,
        IUpdatePositionSizeUtils.IncreasePositionSizeValues memory _values,
        uint256 _price,
        uint256 _expectedPrice,
        uint256 _maxSlippageP
    ) internal pure {
        uint256 maxSlippage = (uint256(_expectedPrice) * _maxSlippageP) / 100 / 1e3;

        // 1. Check if the price after impact is within slippage limits
        if (_existingTrade.long) {
            if (_values.priceAfterImpact > _expectedPrice + maxSlippage) {
                revert IGeneralErrors.Slippage();
            }
        } else {
            if (_values.priceAfterImpact < _expectedPrice - maxSlippage) {
                revert IGeneralErrors.Slippage();
            }
        }

        // 2. Check if TP (Take Profit) has been reached
        if (_existingTrade.tp > 0) {
            if (_existingTrade.long) {
                if (_price >= _existingTrade.tp) {
                    revert IGeneralErrors.TpReached();
                }
            } else {
                if (_price <= _existingTrade.tp) {
                    revert IGeneralErrors.TpReached();
                }
            }
        }

        // 3. Check if SL (Stop Loss) has been reached
        if (_existingTrade.sl > 0) {
            if (_existingTrade.long) {
                if (_price <= _existingTrade.sl) {
                    revert IGeneralErrors.SlReached();
                }
            } else {
                if (_price >= _existingTrade.sl) {
                    revert IGeneralErrors.SlReached();
                }
            }
        }

        // 4. Check if current or new liquidation price has been reached
        if (_existingTrade.long) {
            if (_price <= _values.existingLiqPrice || _price <= _values.newLiqPrice) {
                revert IGeneralErrors.LiqReached();
            }
        } else {
            if (_price >= _values.existingLiqPrice || _price >= _values.newLiqPrice) {
                revert IGeneralErrors.LiqReached();
            }
        }
    }

    /**
     * @dev Updates trade (for successful request)
     * @param _existingTrade existing trade data
     * @param _values pre-calculated useful values
     */
    function updateTradeSuccess(
        ITradingStorage.Trade memory _existingTrade,
        IUpdatePositionSizeUtils.IncreasePositionSizeValues memory _values
    ) internal {
        // 1. Send borrowing fee to vault
        TradingCommonUtils.handleTradePnl(
            _existingTrade,
            0, // collateralSentToTrader = 0
            int256(_values.borrowingFeeCollateral),
            _values.borrowingFeeCollateral
        );

        // 2. Update trade in storage
        _getMultiCollatDiamond().updateTradePosition(
            ITradingStorage.Id(_existingTrade.user, _existingTrade.index),
            uint120(_values.newCollateralAmount),
            uint24(_values.newLeverage),
            uint64(_values.newOpenPrice),
            true // refresh liquidation params
        );

        // 3. Reset trade borrowing fees to zero
        _getMultiCollatDiamond().resetTradeBorrowingFees(
            _existingTrade.collateralIndex,
            _existingTrade.user,
            _existingTrade.pairIndex,
            _existingTrade.index,
            _existingTrade.long
        );
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }
}
