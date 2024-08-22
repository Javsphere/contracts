// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../../interfaces/trade/IJavMultiCollatDiamond.sol";
import "./IncreasePositionSizeUtils.sol";
import "./DecreasePositionSizeUtils.sol";

import "../ConstantsUtils.sol";
import "../TradingCommonUtils.sol";

/**
 *
 * @dev This is an external library for position size updates lifecycles
 * @dev Used by JavTrading and GNSTradingCallbacks facets
 */
library UpdatePositionSizeUtils {
    /**
     * @dev Initiate increase position size order, done in 2 steps because position size changes
     * @param _input request increase position size input struct
     */
    function increasePositionSize(
        IUpdatePositionSizeUtils.IncreasePositionSizeInput memory _input
    ) external {
        // 1. Base validation
        ITradingStorage.Trade memory trade = _baseValidateRequest(_input.user, _input.index);

        // 2. Increase position size validation
        IncreasePositionSizeUtils.validateRequest(trade, _input);

        // 3. Transfer collateral delta from trader to diamond contract (nothing transferred for leverage update)
        TradingCommonUtils.transferCollateralFrom(
            trade.collateralIndex,
            _input.user,
            _input.collateralDelta
        );

        // 4. Refresh trader fee tier cache
        TradingCommonUtils.updateFeeTierPoints(
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            0
        );

        // 5. Prepare vars
        IUpdatePositionSizeUtils.IncreasePositionSizeValues memory values;
        uint256 price = _getMultiCollatDiamond().getPrice(trade.pairIndex);

        values = IncreasePositionSizeUtils.prepareValues(
            trade,
            uint120(_input.collateralDelta),
            _input.leverageDelta,
            uint64(price)
        );

        // 6 Further validation
        IncreasePositionSizeUtils.validateValues(
            trade,
            values,
            price,
            _input.expectedPrice,
            _input.maxSlippageP
        );

        // 7.1 Update trade collateral / leverage / open price in storage, and reset trade borrowing fees
        IncreasePositionSizeUtils.updateTradeSuccess(trade, values);

        // 7.2 Distribute opening fees and store fee tier points for position size delta
        TradingCommonUtils.processOpeningFees(
            trade,
            values.positionSizeCollateralDelta,
            ITradingStorage.PendingOrderType.MARKET_PARTIAL_OPEN
        );

        emit IUpdatePositionSizeUtils.PositionSizeIncreaseExecuted(
            ITradingStorage.Id({user: _input.user, index: _input.index}),
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            trade.index,
            price,
            _input.collateralDelta,
            _input.leverageDelta,
            values
        );
    }

    /**
     * @dev Initiate decrease position size order, done in 2 steps because position size changes
     * @param _input request decrease position size input struct
     */
    function decreasePositionSize(
        IUpdatePositionSizeUtils.DecreasePositionSizeInput memory _input
    ) external {
        // 1. Base validation
        ITradingStorage.Trade memory trade = _baseValidateRequest(_input.user, _input.index);

        // 2. Decrease position size validation
        DecreasePositionSizeUtils.validateRequest(trade, _input);

        // 3. Refresh trader fee tier cache
        TradingCommonUtils.updateFeeTierPoints(
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            0
        );

        IUpdatePositionSizeUtils.DecreasePositionSizeValues memory values;
        uint256 price = _getMultiCollatDiamond().getPrice(trade.pairIndex);

        // 4.1 Prepare useful values (position size delta, closing fees, borrowing fees, etc.)
        values = DecreasePositionSizeUtils.prepareValues(
            trade,
            uint120(_input.collateralDelta),
            _input.leverageDelta,
            uint64(price)
        );

        // 4.2 Further validation
        if (
            (trade.long && price <= values.existingLiqPrice) ||
            (!trade.long && price >= values.existingLiqPrice)
        ) revert IGeneralErrors.LiqReached();

        // 5.1 Send collateral delta (partial trade value - fees) if positive or remove from trade collateral if negative
        // Then update trade collateral / leverage in storage, and reset trade borrowing fees
        DecreasePositionSizeUtils.updateTradeSuccess(trade, values);

        // 5.2 Distribute closing fees
        TradingCommonUtils.distributeStakingReward(
            trade.collateralIndex,
            trade.user,
            values.gnsStakingFeeCollateral
        );
        TradingCommonUtils.distributeVaultFeeCollateral(
            trade.collateralIndex,
            trade.user,
            values.vaultFeeCollateral
        );

        // 5.3 Store trader fee tier points for position size delta
        TradingCommonUtils.updateFeeTierPoints(
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            values.positionSizeCollateralDelta
        );

        emit IUpdatePositionSizeUtils.PositionSizeDecreaseExecuted(
            ITradingStorage.Id({user: _input.user, index: _input.index}),
            trade.collateralIndex,
            trade.user,
            trade.pairIndex,
            trade.index,
            price,
            _input.collateralDelta,
            _input.leverageDelta,
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
     * @dev Basic validation for increase/decrease position size request
     * @param _trader trader address
     * @param _index trade index
     */
    function _baseValidateRequest(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.Trade memory trade) {
        trade = _getMultiCollatDiamond().getTrade(_trader, _index);

        // 1. Check trade exists
        if (!trade.isOpen) revert IGeneralErrors.DoesntExist();

        // 2. Revert if collateral not active
        if (!_getMultiCollatDiamond().isCollateralActive(trade.collateralIndex))
            revert IGeneralErrors.InvalidCollateralIndex();
    }
}
