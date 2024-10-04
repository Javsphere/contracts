// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/leverageX/IJavMultiCollatDiamond.sol";
import "../../interfaces/leverageX/IJavBorrowingProvider.sol";
import "../../interfaces/IRewardsDistributor.sol";

import "./StorageUtils.sol";
import "./AddressStoreUtils.sol";
import "./TradingCommonUtils.sol";
import "./ConstantsUtils.sol";

/**
 * @custom:version 8
 * @dev TradingClose facet internal library
 */

library TradingProcessingUtils {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e10;
    uint256 private constant MAX_OPEN_NEGATIVE_PNL_P = 40 * 1e10; // -40% PNL
    uint256 private constant LIQ_THRESHOLD_P = 90; // -90% pnl

    /**
     * @dev Modifier to only allow trading action when trading is activated (= revert if not activated)
     */
    modifier tradingActivated() {
        if (
            _getMultiCollatDiamond().getTradingActivated() !=
            ITradingStorage.TradingActivated.ACTIVATED
        ) revert IGeneralErrors.GeneralPaused();
        _;
    }

    /**
     * @dev Modifier to only allow trading action when trading is activated or close only (= revert if paused)
     */
    modifier tradingActivatedOrCloseOnly() {
        if (
            _getMultiCollatDiamond().getTradingActivated() ==
            ITradingStorage.TradingActivated.PAUSED
        ) revert IGeneralErrors.GeneralPaused();
        _;
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function initializeTradingProcessing(uint8 _vaultClosingFeeP) internal {
        updateVaultClosingFeeP(_vaultClosingFeeP);
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function updateVaultClosingFeeP(uint8 _valueP) internal {
        if (_valueP > 100) revert IGeneralErrors.AboveMax();

        _getStorage().vaultClosingFeeP = _valueP;

        emit ITradingProcessingUtils.VaultClosingFeePUpdated(_valueP);
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function claimPendingGovFees() internal {
        uint8 collateralsCount = _getMultiCollatDiamond().getCollateralsCount();
        for (uint8 i = 1; i <= collateralsCount; ++i) {
            uint256 feesAmountCollateral = _getStorage().pendingGovFees[i];

            if (feesAmountCollateral > 0) {
                _getStorage().pendingGovFees[i] = 0;

                TradingCommonUtils.transferCollateralTo(i, msg.sender, feesAmountCollateral);

                emit ITradingProcessingUtils.PendingGovFeesClaimed(i, feesAmountCollateral);
            }
        }
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function getVaultClosingFeeP() internal view returns (uint8) {
        return _getStorage().vaultClosingFeeP;
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function getPendingGovFeesCollateral(uint8 _collateralIndex) internal view returns (uint256) {
        return _getStorage().pendingGovFees[_collateralIndex];
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function validateTriggerOpenOrder(
        ITradingStorage.Id memory _tradeId,
        ITradingStorage.PendingOrder memory _pendingOrder
    )
        internal
        view
        returns (
            ITradingStorage.Trade memory t,
            ITradingProcessing.CancelReason cancelReason,
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            bool exactExecution
        )
    {
        if (
            _pendingOrder.orderType != ITradingStorage.PendingOrderType.LIMIT_OPEN &&
            _pendingOrder.orderType != ITradingStorage.PendingOrderType.STOP_OPEN
        ) {
            revert IGeneralErrors.WrongOrderType();
        }

        t = _getTrade(_tradeId.user, _tradeId.index);

        // Return early if trade is not open
        if (!t.isOpen) {
            cancelReason = ITradingProcessing.CancelReason.NO_TRADE;
            return (t, cancelReason, priceImpactP, priceAfterImpact, exactExecution);
        }

        exactExecution = _pendingOrder.price == t.openPrice;

        (priceImpactP, priceAfterImpact, cancelReason) = _openTradePrep(
            t,
            exactExecution ? t.openPrice : _pendingOrder.price,
            _pendingOrder.price,
            _getMultiCollatDiamond().pairSpreadP(t.pairIndex),
            _getTradeInfo(t.user, t.index).maxSlippageP
        );

        if (
            !exactExecution &&
            (
                t.tradeType == ITradingStorage.TradeType.STOP
                    ? (
                        t.long
                            ? _pendingOrder.price < t.openPrice
                            : _pendingOrder.price > t.openPrice
                    )
                    : (
                        t.long
                            ? _pendingOrder.price > t.openPrice
                            : _pendingOrder.price < t.openPrice
                    )
            )
        ) cancelReason = ITradingProcessing.CancelReason.NOT_HIT;
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function validateTriggerCloseOrder(
        ITradingStorage.Id memory _tradeId,
        ITradingStorage.PendingOrder memory _pendingOrder
    )
        internal
        view
        returns (
            ITradingStorage.Trade memory t,
            ITradingProcessing.CancelReason cancelReason,
            ITradingProcessing.Values memory v,
            uint256 priceImpactP
        )
    {
        if (
            _pendingOrder.orderType != ITradingStorage.PendingOrderType.TP_CLOSE &&
            _pendingOrder.orderType != ITradingStorage.PendingOrderType.SL_CLOSE &&
            _pendingOrder.orderType != ITradingStorage.PendingOrderType.LIQ_CLOSE
        ) {
            revert IGeneralErrors.WrongOrderType();
        }

        t = _getTrade(_tradeId.user, _tradeId.index);
        ITradingStorage.TradeInfo memory i = _getTradeInfo(_tradeId.user, _tradeId.index);

        // Return early if trade is not open or market is closed
        if (cancelReason != ITradingProcessing.CancelReason.NONE)
            return (t, cancelReason, v, priceImpactP);

        if (_pendingOrder.orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE) {
            v.liqPrice = TradingCommonUtils.getTradeLiquidationPrice(t, true);
        }

        uint256 triggerPrice = _pendingOrder.orderType == ITradingStorage.PendingOrderType.TP_CLOSE
            ? t.tp
            : (
                _pendingOrder.orderType == ITradingStorage.PendingOrderType.SL_CLOSE
                    ? t.sl
                    : v.liqPrice
            );

        v.exactExecution =
            (triggerPrice > 0 && _pendingOrder.price == triggerPrice) ||
            triggerPrice == 1;
        v.executionPrice = v.exactExecution && triggerPrice != 1
            ? triggerPrice
            : _pendingOrder.price;

        // Apply closing spread and price impact for TPs and SLs, not liquidations (because trade value is 0 already)
        if (_pendingOrder.orderType != ITradingStorage.PendingOrderType.LIQ_CLOSE) {
            (priceImpactP, v.executionPrice, ) = TradingCommonUtils.getTradeClosingPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(
                    t,
                    v.executionPrice,
                    _getMultiCollatDiamond().pairSpreadP(t.pairIndex),
                    TradingCommonUtils.getPositionSizeCollateral(t.collateralAmount, t.leverage)
                )
            );
        }

        uint256 maxSlippage = (triggerPrice *
            (i.maxSlippageP > 0 ? i.maxSlippageP : ConstantsUtils.DEFAULT_MAX_CLOSING_SLIPPAGE_P)) /
            100 /
            1e3;

        cancelReason = (v.exactExecution ||
            (_pendingOrder.orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE &&
                (t.long ? _pendingOrder.price <= v.liqPrice : _pendingOrder.price >= v.liqPrice)) ||
            (_pendingOrder.orderType == ITradingStorage.PendingOrderType.TP_CLOSE &&
                t.tp > 0 &&
                (t.long ? _pendingOrder.price >= t.tp : _pendingOrder.price <= t.tp)) ||
            (_pendingOrder.orderType == ITradingStorage.PendingOrderType.SL_CLOSE &&
                t.sl > 0 &&
                (t.long ? _pendingOrder.price <= t.sl : _pendingOrder.price >= t.sl)))
            ? (
                _pendingOrder.orderType != ITradingStorage.PendingOrderType.LIQ_CLOSE &&
                    (
                        t.long
                            ? v.executionPrice < triggerPrice - maxSlippage
                            : v.executionPrice > triggerPrice + maxSlippage
                    )
                    ? ITradingProcessing.CancelReason.SLIPPAGE
                    : ITradingProcessing.CancelReason.NONE
            )
            : ITradingProcessing.CancelReason.NOT_HIT;
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRADING_CLOSE_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (ITradingProcessing.TradingProcessingStorage storage s)
    {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }

    function openTradeMarketOrder(ITradingStorage.PendingOrder memory _pendingOrder) internal {
        ITradingStorage.Trade memory t = _pendingOrder.trade;

        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: _pendingOrder.trade.user,
            index: _pendingOrder.trade.index
        });

        (
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            ITradingProcessing.CancelReason cancelReason
        ) = _openTradePrep(
                t,
                _pendingOrder.price,
                _pendingOrder.price,
                _getMultiCollatDiamond().pairSpreadP(t.pairIndex),
                _pendingOrder.maxSlippageP
            );

        t.openPrice = uint64(priceAfterImpact);

        if (cancelReason == ITradingProcessing.CancelReason.NONE) {
            t = _registerTrade(t, _pendingOrder);

            emit ITradingProcessingUtils.MarketExecuted(
                orderId,
                t,
                true,
                t.openPrice,
                priceImpactP,
                0,
                0,
                _getCollateralPriceUsd(t.collateralIndex)
            );
        } else {
            // Gov fee to pay for oracle cost
            TradingCommonUtils.updateFeeTierPoints(t.collateralIndex, t.user, t.pairIndex, 0);
            uint256 govFees = TradingCommonUtils.distributeGovFeeCollateral(
                t.collateralIndex,
                t.user,
                t.pairIndex,
                TradingCommonUtils.getMinPositionSizeCollateral(t.collateralIndex, t.pairIndex) / 2, // use min fee / 2
                0
            );
            TradingCommonUtils.transferCollateralTo(
                t.collateralIndex,
                t.user,
                t.collateralAmount - govFees
            );

            emit ITradingProcessingUtils.MarketOpenCanceled(
                orderId,
                t.user,
                t.pairIndex,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function closeTradeMarketOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal tradingActivatedOrCloseOnly {
        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: _pendingOrder.trade.user,
            index: _pendingOrder.trade.index
        });

        ITradingStorage.Trade memory t = _getTrade(
            _pendingOrder.trade.user,
            _pendingOrder.trade.index
        );

        (uint256 priceImpactP, uint256 priceAfterImpact, ) = TradingCommonUtils
            .getTradeClosingPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(
                    t,
                    _pendingOrder.price,
                    _getMultiCollatDiamond().pairSpreadP(t.pairIndex),
                    TradingCommonUtils.getPositionSizeCollateral(t.collateralAmount, t.leverage)
                )
            );

        ITradingProcessing.CancelReason cancelReason;
        {
            cancelReason = !t.isOpen
                ? ITradingProcessing.CancelReason.NO_TRADE
                : _pendingOrder.price == 0
                ? ITradingProcessing.CancelReason.MARKET_CLOSED
                : ITradingProcessing.CancelReason.NONE;
        }

        if (cancelReason != ITradingProcessing.CancelReason.NO_TRADE) {
            ITradingProcessing.Values memory v;

            if (cancelReason == ITradingProcessing.CancelReason.NONE) {
                v.profitP = TradingCommonUtils.getPnlPercent(
                    t.openPrice,
                    uint64(priceAfterImpact),
                    t.long,
                    t.leverage
                );

                v.amountSentToTrader = _unregisterTrade(t, v.profitP, _pendingOrder.orderType);

                emit ITradingProcessingUtils.MarketExecuted(
                    orderId,
                    t,
                    false,
                    uint64(priceAfterImpact),
                    priceImpactP,
                    v.profitP,
                    v.amountSentToTrader,
                    _getCollateralPriceUsd(t.collateralIndex)
                );
            } else {
                // Charge gov fee
                TradingCommonUtils.updateFeeTierPoints(t.collateralIndex, t.user, t.pairIndex, 0);
                uint256 govFee = TradingCommonUtils.distributeGovFeeCollateral(
                    t.collateralIndex,
                    t.user,
                    t.pairIndex,
                    TradingCommonUtils.getMinPositionSizeCollateral(
                        t.collateralIndex,
                        t.pairIndex
                    ) / 2, // use min fee / 2
                    0
                );

                // Deduct from trade collateral
                _getMultiCollatDiamond().updateTradeCollateralAmount(
                    ITradingStorage.Id({user: t.user, index: t.index}),
                    t.collateralAmount - uint120(govFee)
                );
            }
        }

        if (cancelReason != ITradingProcessing.CancelReason.NONE) {
            emit ITradingProcessingUtils.MarketCloseCanceled(
                orderId,
                t.user,
                t.pairIndex,
                t.index,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function executeTriggerOpenOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal tradingActivated {
        if (!_pendingOrder.isOpen) {
            return;
        }

        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: _pendingOrder.trade.user,
            index: _pendingOrder.trade.index
        });

        // Ensure state conditions for executing close order trigger are met
        (
            ITradingStorage.Trade memory t,
            ITradingProcessing.CancelReason cancelReason,
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            bool exactExecution
        ) = validateTriggerOpenOrder(orderId, _pendingOrder);

        if (cancelReason == ITradingProcessing.CancelReason.NONE) {
            // Unregister open order
            _getMultiCollatDiamond().closeTrade(ITradingStorage.Id({user: t.user, index: t.index}));

            // Store trade
            t.openPrice = uint64(priceAfterImpact);
            t.tradeType = ITradingStorage.TradeType.TRADE;
            t = _registerTrade(t, _pendingOrder);

            emit ITradingProcessingUtils.LimitExecuted(
                orderId,
                t,
                _pendingOrder.user,
                _pendingOrder.orderType,
                t.openPrice,
                priceImpactP,
                0,
                0,
                _getCollateralPriceUsd(t.collateralIndex),
                exactExecution
            );
        } else {
            emit ITradingProcessingUtils.TriggerOrderCanceled(
                orderId,
                _pendingOrder.user,
                _pendingOrder.orderType,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function executeTriggerCloseOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal tradingActivatedOrCloseOnly {
        if (!_pendingOrder.isOpen) return;

        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: _pendingOrder.trade.user,
            index: _pendingOrder.trade.index
        });

        // Ensure state conditions for executing close order trigger are met
        (
            ITradingStorage.Trade memory t,
            ITradingProcessing.CancelReason cancelReason,
            ITradingProcessing.Values memory v,
            uint256 priceImpactP
        ) = validateTriggerCloseOrder(orderId, _pendingOrder);

        if (cancelReason == ITradingProcessing.CancelReason.NONE) {
            v.profitP = TradingCommonUtils.getPnlPercent(
                t.openPrice,
                uint64(v.executionPrice),
                t.long,
                t.leverage
            );
            v.amountSentToTrader = _unregisterTrade(t, v.profitP, _pendingOrder.orderType);

            emit ITradingProcessingUtils.LimitExecuted(
                orderId,
                t,
                _pendingOrder.user,
                _pendingOrder.orderType,
                v.executionPrice,
                priceImpactP,
                v.profitP,
                v.amountSentToTrader,
                _getCollateralPriceUsd(t.collateralIndex),
                v.exactExecution
            );
        } else {
            emit ITradingProcessingUtils.TriggerOrderCanceled(
                orderId,
                _pendingOrder.user,
                _pendingOrder.orderType,
                cancelReason
            );
        }
    }

    /**
     * @dev Makes pre-trade checks: price impact, if trade should be cancelled based on parameters like: PnL, leverage, slippage, etc.
     * @param _trade trade input
     * @param _executionPrice execution price (1e10 precision)
     * @param _marketPrice market price (1e10 precision)
     * @param _spreadP spread % (1e10 precision)
     * @param _maxSlippageP max slippage % (1e3 precision)
     */
    function _openTradePrep(
        ITradingStorage.Trade memory _trade,
        uint256 _executionPrice,
        uint256 _marketPrice,
        uint256 _spreadP,
        uint256 _maxSlippageP
    )
        internal
        view
        returns (
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            ITradingProcessing.CancelReason cancelReason
        )
    {
        uint256 positionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
            _trade.collateralAmount,
            _trade.leverage
        );

        (priceImpactP, priceAfterImpact) = TradingCommonUtils.getTradeOpeningPriceImpact(
            ITradingCommonUtils.TradePriceImpactInput(
                _trade,
                _executionPrice,
                _spreadP,
                positionSizeCollateral
            )
        );

        uint256 maxSlippage = (uint256(_trade.openPrice) * _maxSlippageP) / 100 / 1e3;

        cancelReason = _marketPrice == 0
            ? ITradingProcessing.CancelReason.MARKET_CLOSED
            : (
                (
                    _trade.long
                        ? priceAfterImpact > _trade.openPrice + maxSlippage
                        : priceAfterImpact < _trade.openPrice - maxSlippage
                )
                    ? ITradingProcessing.CancelReason.SLIPPAGE
                    : (_trade.tp > 0 &&
                        (
                            _trade.long
                                ? priceAfterImpact >= _trade.tp
                                : priceAfterImpact <= _trade.tp
                        ))
                    ? ITradingProcessing.CancelReason.TP_REACHED
                    : (_trade.sl > 0 &&
                        (_trade.long ? _executionPrice <= _trade.sl : _executionPrice >= _trade.sl))
                    ? ITradingProcessing.CancelReason.SL_REACHED
                    : !TradingCommonUtils.isWithinExposureLimits(
                        _trade.collateralIndex,
                        _trade.pairIndex,
                        _trade.long,
                        positionSizeCollateral
                    )
                    ? ITradingProcessing.CancelReason.EXPOSURE_LIMITS
                    : (priceImpactP * _trade.leverage) / 1e3 >
                        ConstantsUtils.MAX_OPEN_NEGATIVE_PNL_P
                    ? ITradingProcessing.CancelReason.PRICE_IMPACT
                    : _trade.leverage >
                        _getMultiCollatDiamond().pairMaxLeverage(_trade.pairIndex) * 1e3
                    ? ITradingProcessing.CancelReason.MAX_LEVERAGE
                    : ITradingProcessing.CancelReason.NONE
            );
    }

    /**
     * @dev Registers a trade in storage, and handles all fees and rewards
     * @param _trade Trade to register
     * @param _pendingOrder Corresponding pending order
     * @return Final registered trade
     */
    function _registerTrade(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal returns (ITradingStorage.Trade memory) {
        // 1. Deduct gov fee, GNS staking fee (previously dev fee), Market/Limit fee
        _trade.collateralAmount -= TradingCommonUtils.processOpeningFees(
            _trade,
            TradingCommonUtils.getPositionSizeCollateral(_trade.collateralAmount, _trade.leverage),
            _pendingOrder.orderType
        );

        // 2. Store final trade in storage contract
        ITradingStorage.TradeInfo memory tradeInfo;
        _trade = _getMultiCollatDiamond().storeTrade(_trade, tradeInfo);

        return _trade;
    }

    /**
     * @dev Unregisters a trade from storage, and handles all fees and rewards
     * @param _trade Trade to unregister
     * @param _profitP Profit percentage (1e10)
     * @param _orderType pending order type
     * @return tradeValueCollateral Amount of collateral sent to trader, collateral + pnl (collateral precision)
     */
    function _unregisterTrade(
        ITradingStorage.Trade memory _trade,
        int256 _profitP,
        ITradingStorage.PendingOrderType _orderType
    ) internal returns (uint256 tradeValueCollateral) {
        // 1. Process closing fees, fill 'v' with closing/trigger fees and collateral left in storage, to avoid stack too deep
        ITradingProcessing.Values memory v = TradingCommonUtils.processClosingFees(
            _trade,
            TradingCommonUtils.getPositionSizeCollateral(_trade.collateralAmount, _trade.leverage),
            _orderType
        );

        // 2. Calculate borrowing fee and net trade value (with pnl and after all closing/holding fees)
        uint256 borrowingFeeCollateral;
        (tradeValueCollateral, borrowingFeeCollateral) = TradingCommonUtils.getTradeValueCollateral(
            _trade,
            _profitP,
            v.closingFeeCollateral + v.triggerFeeCollateral,
            _getMultiCollatDiamond().getCollateral(_trade.collateralIndex).precisionDelta,
            _orderType
        );

        // 3. Take collateral from vault if winning trade or send collateral to vault if losing trade
        TradingCommonUtils.handleTradePnl(
            _trade,
            int256(tradeValueCollateral),
            int256(v.collateralLeftInStorage),
            borrowingFeeCollateral
        );

        // 4. Unregister trade from storage
        _getMultiCollatDiamond().closeTrade(
            ITradingStorage.Id({user: _trade.user, index: _trade.index})
        );
    }

    /**
     * @dev Calculates market execution price for a trade
     * @param _price price of the asset (1e10)
     * @param _spreadP spread percentage (1e10)
     * @param _long true if long, false if short
     */
    function _marketExecutionPrice(
        uint256 _price,
        uint256 _spreadP,
        bool _long
    ) internal pure returns (uint256) {
        uint256 priceDiff = (_price * _spreadP) / 100 / PRECISION;

        return _long ? _price + priceDiff : _price - priceDiff;
    }

    /**
     * @dev Checks if total position size is not higher than maximum allowed open interest for a pair
     * @param _collateralIndex index of collateral
     * @param _pairIndex index of pair
     * @param _long true if long, false if short
     * @param _tradeCollateral trade collateral (collateral precision)
     * @param _tradeLeverage trade leverage (1e3)
     */
    function _withinExposureLimits(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        bool _long,
        uint256 _tradeCollateral,
        uint256 _tradeLeverage
    ) internal view returns (bool) {
        uint256 positionSizeCollateral = (_tradeCollateral * _tradeLeverage) / 1e3;

        return
            _getMultiCollatDiamond().getPairOiCollateral(_collateralIndex, _pairIndex, _long) +
                positionSizeCollateral <=
            _getMultiCollatDiamond().getPairMaxOiCollateral(_collateralIndex, _pairIndex) &&
            _getMultiCollatDiamond().withinMaxBorrowingGroupOi(
                _collateralIndex,
                _pairIndex,
                _long,
                positionSizeCollateral
            );
    }

    /**
     * @dev Returns collateral price in USD
     * @param _collateralIndex Collateral index
     * @return Collateral price in USD
     */
    function _getCollateralPriceUsd(uint8 _collateralIndex) internal view returns (uint256) {
        return _getMultiCollatDiamond().getCollateralPriceUsd(_collateralIndex);
    }

    /**
     * @dev Returns trade from storage
     * @param _trader Trader address
     * @param _index Trade index
     * @return Trade
     */
    function _getTrade(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.Trade memory) {
        return _getMultiCollatDiamond().getTrade(_trader, _index);
    }

    /**
     * @dev Returns trade info from storage
     * @param _trader Trader address
     * @param _index Trade index
     * @return TradeInfo
     */
    function _getTradeInfo(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.TradeInfo memory) {
        return _getMultiCollatDiamond().getTradeInfo(_trader, _index);
    }
}
