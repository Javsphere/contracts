// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/trade/IJavMultiCollatDiamond.sol";
import "../../interfaces/trade/IJavBorrowingProvider.sol";
import "../../interfaces/IRewardsDistributor.sol";

import "./StorageUtils.sol";
import "./AddressStoreUtils.sol";
import "./TradingCommonUtils.sol";

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

        _getMultiCollatDiamond().validateTrade(t);

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
            uint256 collateralPriceUsd;
            (t, collateralPriceUsd) = _registerTrade(t, _pendingOrder);

            emit ITradingProcessingUtils.MarketExecuted(
                t,
                true,
                t.openPrice,
                priceImpactP,
                0,
                0,
                collateralPriceUsd
            );
        } else {
            // Gov fee to pay for oracle cost
            TradingCommonUtils.updateFeeTierPoints(t.collateralIndex, t.user, t.pairIndex, 0);
            uint256 govFees = TradingCommonUtils.distributeGovFeeCollateral(
                t.collateralIndex,
                t.user,
                t.pairIndex,
                TradingCommonUtils.getPositionSizeCollateral(t.collateralAmount, t.leverage),
                0
            );
            TradingCommonUtils.transferCollateralTo(
                t.collateralIndex,
                t.user,
                t.collateralAmount - govFees
            );

            emit ITradingProcessingUtils.MarketOpenCanceled(t.user, t.pairIndex, cancelReason);
        }
    }

    /**
     * @dev Check ITradingProcessingUtils interface for documentation
     */
    function closeTradeMarketOrder(
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal tradingActivatedOrCloseOnly {
        ITradingStorage.Trade memory t = _getTrade(
            _pendingOrder.trade.user,
            _pendingOrder.trade.index
        );

        ITradingProcessing.CancelReason cancelReason = !t.isOpen
            ? ITradingProcessing.CancelReason.NO_TRADE
            : (
                _pendingOrder.price == 0
                    ? ITradingProcessing.CancelReason.MARKET_CLOSED
                    : ITradingProcessing.CancelReason.NONE
            );

        if (cancelReason != ITradingProcessing.CancelReason.NO_TRADE) {
            ITradingProcessing.Values memory v;
            v.positionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
                t.collateralAmount,
                t.leverage
            );

            if (cancelReason == ITradingProcessing.CancelReason.NONE) {
                v.profitP = _getMultiCollatDiamond().getPnlPercent(
                    t.openPrice,
                    _pendingOrder.price,
                    t.long,
                    t.leverage
                );

                v.amountSentToTrader = _unregisterTrade(
                    t,
                    _pendingOrder.orderType,
                    true,
                    v.profitP,
                    (v.positionSizeCollateral *
                        _getMultiCollatDiamond().pairCloseFeeP(t.pairIndex)) /
                        100 /
                        PRECISION,
                    (v.positionSizeCollateral *
                        _getMultiCollatDiamond().pairTriggerOrderFeeP(t.pairIndex)) /
                        100 /
                        PRECISION
                );

                emit ITradingProcessingUtils.MarketExecuted(
                    t,
                    false,
                    _pendingOrder.price,
                    0,
                    v.profitP,
                    v.amountSentToTrader,
                    _getCollateralPriceUsd(t.collateralIndex)
                );
            } else {
                // Recalculate trader fee tier cache
                TradingCommonUtils.updateFeeTierPoints(t.collateralIndex, t.user, t.pairIndex, 0);

                // Charge gov fee on trade
                uint256 govFee = TradingCommonUtils.distributeGovFeeCollateral(
                    t.collateralIndex,
                    t.user,
                    t.pairIndex,
                    v.positionSizeCollateral,
                    0
                );
                _getMultiCollatDiamond().updateTradeCollateralAmount(
                    ITradingStorage.Id({user: t.user, index: t.index}),
                    t.collateralAmount - uint120(govFee)
                );

                // Remove OI corresponding to gov fee from price impact windows and borrowing fees
                uint256 levGovFee = (govFee * t.leverage) / 1e3;
                TradingCommonUtils.removeOiCollateral(t, levGovFee);
            }
        }

        if (cancelReason != ITradingProcessing.CancelReason.NONE) {
            emit ITradingProcessingUtils.MarketCloseCanceled(
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

        ITradingStorage.Trade memory t = _getTrade(
            _pendingOrder.trade.user,
            _pendingOrder.trade.index
        );

        ITradingProcessing.CancelReason cancelReason = !t.isOpen
            ? ITradingProcessing.CancelReason.NO_TRADE
            : ITradingProcessing.CancelReason.NONE;

        if (cancelReason == ITradingProcessing.CancelReason.NONE) {
            cancelReason = _pendingOrder.price == t.openPrice
                ? ITradingProcessing.CancelReason.NONE
                : ITradingProcessing.CancelReason.NOT_HIT;

            (
                uint256 priceImpactP,
                uint256 priceAfterImpact,
                ITradingProcessing.CancelReason _cancelReason
            ) = _openTradePrep(
                    t,
                    cancelReason == ITradingProcessing.CancelReason.NONE
                        ? t.openPrice
                        : _pendingOrder.price,
                    _pendingOrder.price,
                    _getMultiCollatDiamond().pairSpreadP(t.pairIndex),
                    _getMultiCollatDiamond().getTradeInfo(t.user, t.index).maxSlippageP
                );

            bool exactExecution = cancelReason == ITradingProcessing.CancelReason.NONE;

            cancelReason = !exactExecution &&
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
                ? ITradingProcessing.CancelReason.NOT_HIT
                : _cancelReason;

            if (cancelReason == ITradingProcessing.CancelReason.NONE) {
                // Unregister open order
                _getMultiCollatDiamond().closeTrade(
                    ITradingStorage.Id({user: t.user, index: t.index})
                );

                // Store trade
                t.openPrice = uint64(priceAfterImpact);
                t.tradeType = ITradingStorage.TradeType.TRADE;
                uint256 collateralPriceUsd;
                (t, collateralPriceUsd) = _registerTrade(t, _pendingOrder);

                emit ITradingProcessingUtils.LimitExecuted(
                    t,
                    _pendingOrder.user,
                    _pendingOrder.orderType,
                    t.openPrice,
                    priceImpactP,
                    0,
                    0,
                    collateralPriceUsd,
                    exactExecution
                );
            }
        }

        if (cancelReason != ITradingProcessing.CancelReason.NONE) {
            emit ITradingProcessingUtils.TriggerOrderCanceled(
                _pendingOrder.user,
                _pendingOrder.index,
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
        if (!_pendingOrder.isOpen) {
            return;
        }

        ITradingStorage.Trade memory t = _getTrade(
            _pendingOrder.trade.user,
            _pendingOrder.trade.index
        );

        ITradingProcessing.CancelReason cancelReason = _pendingOrder.price == 0
            ? ITradingProcessing.CancelReason.MARKET_CLOSED
            : (
                !t.isOpen
                    ? ITradingProcessing.CancelReason.NO_TRADE
                    : ITradingProcessing.CancelReason.NONE
            );

        if (cancelReason == ITradingProcessing.CancelReason.NONE) {
            ITradingProcessing.Values memory v;
            v.positionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
                t.collateralAmount,
                t.leverage
            );

            if (_pendingOrder.orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE) {
                v.liqPrice = _getMultiCollatDiamond().getTradeLiquidationPrice(
                    IBorrowingFees.LiqPriceInput(
                        t.collateralIndex,
                        t.user,
                        t.pairIndex,
                        t.index,
                        t.openPrice,
                        t.long,
                        uint256(t.collateralAmount),
                        t.leverage,
                        true
                    )
                );
            }

            v.executionPrice = _pendingOrder.orderType == ITradingStorage.PendingOrderType.TP_CLOSE
                ? t.tp
                : (
                    _pendingOrder.orderType == ITradingStorage.PendingOrderType.SL_CLOSE
                        ? t.sl
                        : v.liqPrice
                );

            v.exactExecution = v.executionPrice > 0 && _pendingOrder.price == v.executionPrice;

            if (v.exactExecution) {
                v.reward1 = _pendingOrder.orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE
                    ? (uint256(t.collateralAmount) * 5) / 100
                    : (v.positionSizeCollateral *
                        _getMultiCollatDiamond().pairTriggerOrderFeeP(t.pairIndex)) /
                        100 /
                        PRECISION;
            } else {
                v.executionPrice = _pendingOrder.price;

                v.reward1 = _pendingOrder.orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE
                    ? (
                        (
                            t.long
                                ? _pendingOrder.price <= v.liqPrice
                                : _pendingOrder.price >= v.liqPrice
                        )
                            ? (uint256(t.collateralAmount) * 5) / 100
                            : 0
                    )
                    : (
                        ((_pendingOrder.orderType == ITradingStorage.PendingOrderType.TP_CLOSE &&
                            t.tp > 0 &&
                            (t.long ? _pendingOrder.price >= t.tp : _pendingOrder.price <= t.tp)) ||
                            (_pendingOrder.orderType == ITradingStorage.PendingOrderType.SL_CLOSE &&
                                t.sl > 0 &&
                                (
                                    t.long
                                        ? _pendingOrder.price <= t.sl
                                        : _pendingOrder.price >= t.sl
                                )))
                            ? (v.positionSizeCollateral *
                                _getMultiCollatDiamond().pairTriggerOrderFeeP(t.pairIndex)) /
                                100 /
                                PRECISION
                            : 0
                    );
            }

            cancelReason = v.reward1 == 0
                ? ITradingProcessing.CancelReason.NOT_HIT
                : ITradingProcessing.CancelReason.NONE;

            // If can be triggered
            if (cancelReason == ITradingProcessing.CancelReason.NONE) {
                v.profitP = _getMultiCollatDiamond().getPnlPercent(
                    t.openPrice,
                    uint64(v.executionPrice),
                    t.long,
                    t.leverage
                );

                v.amountSentToTrader = _unregisterTrade(
                    t,
                    _pendingOrder.orderType,
                    false,
                    v.profitP,
                    _pendingOrder.orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE
                        ? v.reward1
                        : (v.positionSizeCollateral *
                            _getMultiCollatDiamond().pairCloseFeeP(t.pairIndex)) /
                            100 /
                            PRECISION,
                    v.reward1
                );

                emit ITradingProcessingUtils.LimitExecuted(
                    t,
                    _pendingOrder.user,
                    _pendingOrder.orderType,
                    v.executionPrice,
                    0,
                    v.profitP,
                    v.amountSentToTrader,
                    _getCollateralPriceUsd(t.collateralIndex),
                    v.exactExecution
                );
            }
        }

        if (cancelReason != ITradingProcessing.CancelReason.NONE) {
            emit ITradingProcessingUtils.TriggerOrderCanceled(
                _pendingOrder.user,
                _pendingOrder.index,
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
        uint256 usdValue = _getMultiCollatDiamond().getUsdNormalizedValue(
            _trade.collateralIndex,
            TradingCommonUtils.getPositionSizeCollateral(_trade.collateralAmount, _trade.leverage)
        );
        (priceImpactP, priceAfterImpact) = _getMultiCollatDiamond().getTradePriceImpact(
            _marketExecutionPrice(_executionPrice, _spreadP, _trade.long),
            _trade.pairIndex,
            _trade.long,
            usdValue
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
                    : !_withinExposureLimits(
                        _trade.collateralIndex,
                        _trade.pairIndex,
                        _trade.long,
                        _trade.collateralAmount,
                        _trade.leverage
                    )
                    ? ITradingProcessing.CancelReason.EXPOSURE_LIMITS
                    : (priceImpactP * _trade.leverage) / 1e3 > MAX_OPEN_NEGATIVE_PNL_P
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
     * @return Registered trade
     * @return Collateral price in USD (1e8 precision)
     */
    function _registerTrade(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal returns (ITradingStorage.Trade memory, uint256) {
        _trade.collateralAmount -= TradingCommonUtils.processOpeningFees(
            _trade,
            TradingCommonUtils.getPositionSizeCollateral(_trade.collateralAmount, _trade.leverage),
            _pendingOrder.orderType
        );

        // 8. Store final trade in storage contract
        ITradingStorage.TradeInfo memory tradeInfo;
        uint256 collateralPriceUsd = _getCollateralPriceUsd(_trade.collateralIndex);
        tradeInfo.collateralPriceUsd = uint48(collateralPriceUsd);
        _trade = _getMultiCollatDiamond().storeTrade(_trade, tradeInfo);

        // 9. Call other contracts
        TradingCommonUtils.addTradeOiCollateral(_trade);

        return (_trade, collateralPriceUsd);
    }

    /**
     * @dev Unregisters a trade from storage, and handles all fees and rewards
     * @param _trade Trade to unregister
     * @param _marketOrder True if market order, false if limit/stop order
     * @param _percentProfit Profit percentage (1e10)
     * @param _closingFeeCollateral Closing fee in collateral (collateral precision)
     * @param _triggerFeeCollateral Trigger fee or JAV staking reward if market order (collateral precision)
     * @return tradeValueCollateral Amount of collateral sent to trader, collateral + pnl (collateral precision)
     */
    function _unregisterTrade(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.PendingOrderType _orderType,
        bool _marketOrder,
        int256 _percentProfit,
        uint256 _closingFeeCollateral,
        uint256 _triggerFeeCollateral
    ) internal returns (uint256 tradeValueCollateral) {
        ITradingProcessing.Values memory v;
        v.collateralPrecisionDelta = _getMultiCollatDiamond()
            .getCollateral(_trade.collateralIndex)
            .precisionDelta;
        v.positionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
            _trade.collateralAmount,
            _trade.leverage
        );

        // 1. Re-calculate current trader fee tier and apply it
        TradingCommonUtils.updateFeeTierPoints(
            _trade.collateralIndex,
            _trade.user,
            _trade.pairIndex,
            v.positionSizeCollateral
        );
        _closingFeeCollateral = _getMultiCollatDiamond().calculateFeeAmount(
            _trade.user,
            _closingFeeCollateral
        );
        _triggerFeeCollateral = _getMultiCollatDiamond().calculateFeeAmount(
            _trade.user,
            _triggerFeeCollateral
        );

        // 2. Calculate borrowing fee and net trade value (with pnl and after all closing/holding fees)
        {
            uint256 borrowingFeeCollateral;
            (tradeValueCollateral, borrowingFeeCollateral) = _getTradeValue(
                _trade,
                _orderType,
                _percentProfit,
                _closingFeeCollateral + _triggerFeeCollateral,
                v.collateralPrecisionDelta
            );
            emit ITradingProcessingUtils.BorrowingFeeCharged(
                _trade.user,
                _trade.collateralIndex,
                borrowingFeeCollateral
            );
        }

        // 3. Call other contracts
        TradingCommonUtils.removeOiCollateral(_trade, v.positionSizeCollateral);

        // 4. Unregister trade from storage
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({
            user: _trade.user,
            index: _trade.index
        });
        _getMultiCollatDiamond().closeTrade(tradeId);

        // 5. jToken vault reward
        IJavBorrowingProvider borrowingProvider = IJavBorrowingProvider(
            _getMultiCollatDiamond().getBorrowingProvider()
        );
        uint256 vaultClosingFeeP = uint256(_getStorage().vaultClosingFeeP);
        v.reward2 = (_closingFeeCollateral * vaultClosingFeeP) / 100;
        borrowingProvider.distributeReward(_trade.collateralIndex, v.reward2);

        emit ITradingProcessingUtils.JTokenFeeCharged(
            _trade.user,
            _trade.collateralIndex,
            v.reward2
        );

        // 6. JAV staking reward
        v.reward3 =
            (_marketOrder ? _triggerFeeCollateral : (_triggerFeeCollateral * 8) / 10) +
            (_closingFeeCollateral * (100 - vaultClosingFeeP)) /
            100;
        TradingCommonUtils.distributeStakingReward(_trade.collateralIndex, _trade.user, v.reward3);

        // 7. Take collateral from vault if winning trade or send collateral to vault if losing trade
        uint256 collateralLeftInStorage = _trade.collateralAmount - v.reward3 - v.reward2;

        if (tradeValueCollateral > collateralLeftInStorage) {
            borrowingProvider.sendAssets(
                _trade.collateralIndex,
                tradeValueCollateral - collateralLeftInStorage,
                _trade.user
            );
            TradingCommonUtils.transferCollateralTo(
                _trade.collateralIndex,
                _trade.user,
                collateralLeftInStorage
            );
        } else {
            _sendToVault(
                _trade.collateralIndex,
                collateralLeftInStorage - tradeValueCollateral,
                _trade.user
            );
            TradingCommonUtils.transferCollateralTo(
                _trade.collateralIndex,
                _trade.user,
                tradeValueCollateral
            );
        }
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
     * @dev Sends collateral to vault for negative pnl
     * @param _collateralIndex Collateral index
     * @param _amountCollateral Amount of collateral to send to vault (collateral precision)
     * @param _trader Trader address
     */
    function _sendToVault(
        uint8 _collateralIndex,
        uint256 _amountCollateral,
        address _trader
    ) internal {
        IJavBorrowingProvider(_getMultiCollatDiamond().getBorrowingProvider()).receiveAssets(
            _collateralIndex,
            _amountCollateral,
            _trader
        );
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
     * @dev Returns trade value and borrowing fee.
     * @param _trade trade data
     * @param _percentProfit profit percentage (1e10)
     * @param _closingFeesCollateral closing fees in collateral tokens (collateral precision)
     * @param _collateralPrecisionDelta precision delta of collateral (10^18/10^decimals)
     * @return value trade value
     * @return borrowingFeesCollateral borrowing fees in collateral tokens (collateral precision)
     */
    function _getTradeValue(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.PendingOrderType _orderType,
        int256 _percentProfit,
        uint256 _closingFeesCollateral,
        uint128 _collateralPrecisionDelta
    ) internal view returns (uint256 value, uint256 borrowingFeesCollateral) {
        borrowingFeesCollateral = _getMultiCollatDiamond().getTradeBorrowingFee(
            IBorrowingFees.BorrowingFeeInput(
                _trade.collateralIndex,
                _trade.user,
                _trade.pairIndex,
                _trade.index,
                _trade.long,
                _trade.collateralAmount,
                _trade.leverage
            )
        );

        value = TradingCommonUtils.getTradeValuePure(
            _trade.collateralAmount,
            _percentProfit,
            borrowingFeesCollateral,
            _closingFeesCollateral,
            _collateralPrecisionDelta,
            _orderType
        );
    }
}
