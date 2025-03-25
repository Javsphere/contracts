// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/leverageX/types/ITradingStorage.sol";
import "../../interfaces/leverageX/libraries/ITradingCommonUtils.sol";
import "../../interfaces/leverageX/IJavMultiCollatDiamond.sol";
import "../../interfaces/leverageX/IJavBorrowingProvider.sol";
import "../../interfaces/IRewardsDistributor.sol";
import "./ConstantsUtils.sol";
import "./AddressStoreUtils.sol";
import "./TradingProcessingUtils.sol";

/**
 * @dev External library for helper functions commonly used in many places
 */
library TradingCommonUtils {
    using SafeERC20 for IERC20;

    // Pure functions
    /**
     * @dev Returns the current percent profit of a trade (1e10 precision)
     * @param _openPrice trade open price (1e10 precision)
     * @param _currentPrice trade current price (1e10 precision)
     * @param _long true for long, false for short
     * @param _leverage trade leverage (1e3 precision)
     */
    function getPnlPercent(
        uint64 _openPrice,
        uint64 _currentPrice,
        bool _long,
        uint24 _leverage
    ) public view returns (int256 p) {
        int256 pricePrecision = int256(ConstantsUtils.P_10);
        int256 maxPnlP = int256(_getMultiCollatDiamond().getMaxPnlP()) * pricePrecision;
        int256 minPnlP = -100 * int256(ConstantsUtils.P_10);

        int256 openPrice = int256(uint256(_openPrice));
        int256 currentPrice = int256(uint256(_currentPrice));
        int256 leverage = int256(uint256(_leverage));

        p = _openPrice > 0
            ? ((_long ? currentPrice - openPrice : openPrice - currentPrice) *
                100 *
                pricePrecision *
                leverage) /
                openPrice /
                1e3
            : int256(0);

        p = p > maxPnlP
            ? maxPnlP
            : p < minPnlP
                ? minPnlP
                : p;
    }

    /**
     * @dev Returns position size of trade in collateral tokens (avoids overflow from uint120 collateralAmount)
     * @param _collateralAmount collateral of trade
     * @param _leverage leverage of trade (1e3)
     */
    function getPositionSizeCollateral(
        uint120 _collateralAmount,
        uint24 _leverage
    ) public pure returns (uint256) {
        return (uint256(_collateralAmount) * _leverage) / 1e3;
    }

    /**
     * @dev Calculates market execution price for a trade (1e10 precision)
     * @param _price price of the asset (1e10)
     * @param _spreadP spread percentage (1e10)
     * @param _long true if long, false if short
     */
    function getMarketExecutionPrice(
        uint256 _price,
        uint256 _spreadP,
        bool _long,
        bool _open
    ) public pure returns (uint256) {
        _spreadP = _spreadP / 2;

        uint256 priceDiff = (_price * _spreadP) / 100 / ConstantsUtils.P_10;
        if (!_open) _long = !_long; // reverse spread direction on close
        return _long ? _price + priceDiff : _price - priceDiff;
    }

    /**
     * @dev Converts collateral value to USD (1e18 precision)
     * @param _collateralAmount amount of collateral (collateral precision)
     * @param _collateralPrecisionDelta precision delta of collateral (10^18/10^decimals)
     * @param _collateralPriceUsd price of collateral in USD (1e8)
     */
    function convertCollateralToUsd(
        uint256 _collateralAmount,
        uint128 _collateralPrecisionDelta,
        uint256 _collateralPriceUsd
    ) external pure returns (uint256) {
        return (_collateralAmount * _collateralPrecisionDelta * _collateralPriceUsd) / 1e8;
    }

    /**
     * @dev Calculates trade value (useful when closing a trade)
     * @dev Important: does not calculate if trade can be liquidated or not, has to be done by calling function
     * @param _collateral amount of collateral (collateral precision)
     * @param _percentProfit profit percentage (1e10)
     * @param _feesCollateral borrowing fee + closing fee in collateral tokens (collateral precision)
     * @param _collateralPrecisionDelta precision delta of collateral (10^18/10^decimals)
     */
    function getTradeValuePure(
        uint256 _collateral,
        int256 _percentProfit,
        uint256 _feesCollateral,
        uint128 _collateralPrecisionDelta
    ) public pure returns (uint256) {
        int256 precisionDelta = int256(uint256(_collateralPrecisionDelta));

        // Multiply collateral by precisionDelta so we don't lose precision for low decimals
        int256 value = (int256(_collateral) *
            precisionDelta +
            (int256(_collateral) * precisionDelta * _percentProfit) /
            int256(ConstantsUtils.P_10) /
            100) /
            precisionDelta -
            int256(_feesCollateral);

        return value > 0 ? uint256(value) : uint256(0);
    }

    /**
     * @dev Pure function that returns the liquidation pnl % threshold for a trade (1e10)
     * @param _params trade liquidation params
     * @param _leverage trade leverage (1e3 precision)
     */
    function getLiqPnlThresholdP(
        IPairsStorage.GroupLiquidationParams memory _params,
        uint256 _leverage
    ) public pure returns (uint256) {
        // By default use legacy threshold if liquidation params not set (trades opened before v9.2)
        if (_params.maxLiqSpreadP == 0) return ConstantsUtils.LEGACY_LIQ_THRESHOLD_P;

        if (_leverage <= _params.startLeverage) return _params.startLiqThresholdP;
        if (_leverage >= _params.endLeverage) return _params.endLiqThresholdP;

        return
            _params.startLiqThresholdP -
            ((_leverage - _params.startLeverage) *
                (_params.startLiqThresholdP - _params.endLiqThresholdP)) /
            (_params.endLeverage - _params.startLeverage);
    }

    // View functions

    /**
     * @dev Returns position size of trade in collateral tokens (avoids overflow from uint120 collateralAmount)
     * @param _collateralIndex collateral index
     * @param _pairIndex pair index
     */
    function getMinPositionSizeCollateral(
        uint8 _collateralIndex,
        uint256 _pairIndex
    ) public view returns (uint256) {
        return
            _getMultiCollatDiamond().getCollateralFromUsdNormalizedValue(
                _collateralIndex,
                _getMultiCollatDiamond().pairMinPositionSizeUsd(_pairIndex)
            );
    }

    /**
     * @dev Returns position size to use when charging fees
     * @param _collateralIndex collateral index
     * @param _pairIndex pair index
     * @param _positionSizeCollateral trade position size in collateral tokens (collateral precision)
     */
    function getPositionSizeCollateralBasis(
        uint8 _collateralIndex,
        uint256 _pairIndex,
        uint256 _positionSizeCollateral
    ) public view returns (uint256) {
        uint256 minPositionSizeCollateral = getMinPositionSizeCollateral(
            _collateralIndex,
            _pairIndex
        );
        return
            _positionSizeCollateral > minPositionSizeCollateral
                ? _positionSizeCollateral
                : minPositionSizeCollateral;
    }

    /**
     * @dev Checks if total position size is not higher than maximum allowed open interest for a pair
     * @param _collateralIndex index of collateral
     * @param _pairIndex index of pair
     * @param _long true if long, false if short
     * @param _positionSizeCollateralDelta position size delta in collateral tokens (collateral precision)
     */
    function isWithinExposureLimits(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        bool _long,
        uint256 _positionSizeCollateralDelta
    ) public view returns (bool) {
        return
            _getMultiCollatDiamond().getPairOiCollateral(_collateralIndex, _pairIndex, _long) +
                _positionSizeCollateralDelta <=
            _getMultiCollatDiamond().getPairMaxOiCollateral(_collateralIndex, _pairIndex) &&
            _getMultiCollatDiamond().withinMaxBorrowingGroupOi(
                _collateralIndex,
                _pairIndex,
                _long,
                _positionSizeCollateralDelta
            );
    }

    /**
     * @dev Convenient wrapper to return trade borrowing fee in collateral tokens (collateral precision)
     * @param _trade trade input
     */
    function getTradeBorrowingFeeCollateral(
        ITradingStorage.Trade memory _trade
    ) public view returns (uint256) {
        return
            _getMultiCollatDiamond().getTradeBorrowingFee(
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
    }

    /**
     * @dev Convenient wrapper to return trade liquidation price (1e10)
     * @param _trade trade input
     */
    function getTradeLiquidationPrice(
        ITradingStorage.Trade memory _trade,
        bool _useBorrowingFees
    ) external view returns (uint256) {
        return
            _getMultiCollatDiamond().getTradeLiquidationPrice(
                IBorrowingFees.LiqPriceInput(
                    _trade.collateralIndex,
                    _trade.user,
                    _trade.pairIndex,
                    _trade.index,
                    _trade.openPrice,
                    _trade.long,
                    _trade.collateralAmount,
                    _trade.leverage,
                    _useBorrowingFees,
                    _getMultiCollatDiamond().getTradeLiquidationParams(_trade.user, _trade.index)
                )
            );
    }

    /**
     * @dev Returns trade value and borrowing fee in collateral tokens
     * @param _trade trade data
     * @param _percentProfit profit percentage (1e10)
     * @param _closingFeesCollateral closing fees in collateral tokens (collateral precision)
     * @param _collateralPrecisionDelta precision delta of collateral (10^18/10^decimals)
     */
    function getTradeValueCollateral(
        ITradingStorage.Trade memory _trade,
        int256 _percentProfit,
        uint256 _closingFeesCollateral,
        uint128 _collateralPrecisionDelta
    ) public view returns (uint256 valueCollateral, uint256 borrowingFeesCollateral) {
        borrowingFeesCollateral = getTradeBorrowingFeeCollateral(_trade);

        valueCollateral = getTradeValuePure(
            _trade.collateralAmount,
            _percentProfit,
            borrowingFeesCollateral + _closingFeesCollateral,
            _collateralPrecisionDelta
        );
    }

    /**
     * @dev Returns price impact % (1e10), price after spread and impact (1e10)
     * @param _input input data
     */
    function getTradeOpeningPriceImpact(
        ITradingCommonUtils.TradePriceImpactInput memory _input
    ) external view returns (uint256 priceImpactP, uint256 priceAfterImpact) {
        ITradingStorage.Trade memory trade = _input.trade;

        (priceImpactP, priceAfterImpact) = _getMultiCollatDiamond().getTradePriceImpact(
            trade.user,
            getMarketExecutionPrice(_input.marketPrice, _input.spreadP, trade.long, true),
            trade.pairIndex,
            trade.long,
            _getMultiCollatDiamond().getUsdNormalizedValue(
                trade.collateralIndex,
                _input.positionSizeCollateral
            ),
            false,
            true,
            0
        );
    }

    /**
     * @dev Returns price impact % (1e10), price after spread and impact (1e10), and trade value used to know if pnl is positive (collateral precision)
     * @param _input input data
     */
    function getTradeClosingPriceImpact(
        ITradingCommonUtils.TradePriceImpactInput memory _input
    )
        external
        view
        returns (
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            uint256 tradeValueCollateralNoFactor
        )
    {
        ITradingStorage.Trade memory trade = _input.trade;
        ITradingStorage.TradeInfo memory tradeInfo = _getMultiCollatDiamond().getTradeInfo(
            trade.user,
            trade.index
        );

        // 1. Prepare vars
        bool open = false;
        uint256 priceAfterSpread = getMarketExecutionPrice(
            _input.marketPrice,
            _input.spreadP,
            trade.long,
            open
        );
        uint256 positionSizeUsd = _getMultiCollatDiamond().getUsdNormalizedValue(
            trade.collateralIndex,
            _input.positionSizeCollateral
        );

        // 2. Calculate PnL after fees, spread, and price impact without protection factor
        (, uint256 priceNoProtectionFactor) = _getMultiCollatDiamond().getTradePriceImpact(
            trade.user,
            priceAfterSpread,
            trade.pairIndex,
            trade.long,
            positionSizeUsd,
            false, // assume pnl negative, so it doesn't use protection factor
            open,
            tradeInfo.lastPosIncreaseBlock
        );
        int256 pnlPercentNoProtectionFactor = getPnlPercent(
            trade.openPrice,
            uint64(priceNoProtectionFactor),
            trade.long,
            trade.leverage
        );
        (tradeValueCollateralNoFactor, ) = getTradeValueCollateral(
            trade,
            pnlPercentNoProtectionFactor,
            getTotalTradeFeesCollateral(
                trade.collateralIndex,
                trade.user,
                trade.pairIndex,
                getPositionSizeCollateral(trade.collateralAmount, trade.leverage)
            ),
            _getMultiCollatDiamond().getCollateral(trade.collateralIndex).precisionDelta
        );

        (priceImpactP, priceAfterImpact) = _getMultiCollatDiamond().getTradePriceImpact(
            trade.user,
            priceAfterSpread,
            trade.pairIndex,
            trade.long,
            positionSizeUsd,
            tradeValueCollateralNoFactor > trade.collateralAmount, // _isPnlPositive = true when net pnl after fees is positive
            open,
            tradeInfo.lastPosIncreaseBlock
        );
    }

    /**
     * @dev Returns a trade's liquidation threshold % (1e10)
     * @param _trade trade struct
     */
    function getTradeLiqPnlThresholdP(
        ITradingStorage.Trade memory _trade
    ) public view returns (uint256) {
        return
            getLiqPnlThresholdP(
                _getMultiCollatDiamond().getTradeLiquidationParams(_trade.user, _trade.index),
                _trade.leverage
            );
    }

    /**
     * @dev Returns all fees for a trade in collateral tokens
     * @param _collateralIndex collateral index
     * @param _trader address of trader
     * @param _pairIndex index of pair
     * @param _positionSizeCollateral position size in collateral tokens (collateral precision)
     */
    function getTotalTradeFeesCollateral(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex,
        uint256 _positionSizeCollateral
    ) public view returns (uint256) {
        return
            _getMultiCollatDiamond().calculateFeeAmount(
                _trader,
                (getPositionSizeCollateralBasis(
                    _collateralIndex,
                    _pairIndex,
                    _positionSizeCollateral
                ) * _getMultiCollatDiamond().pairTotalPositionSizeFeeP(_pairIndex)) /
                    ConstantsUtils.P_10 /
                    100
            );
    }

    /**
     * @dev Returns all fees for a trade in collateral tokens
     * @param _collateralIndex collateral index
     * @param _trader address of trader
     * @param _pairIndex index of pair
     * @param _collateralAmount trade collateral amount (collateral precision)
     * @param _positionSizeCollateral trade position size in collateral tokens (collateral precision)
     * @param _orderType corresponding order type
     */
    function getTradeFeesCollateral(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex,
        uint256 _collateralAmount,
        uint256 _positionSizeCollateral,
        ITradingStorage.PendingOrderType _orderType
    ) public view returns (IPairsStorage.TradeFees memory tradeFees) {
        IPairsStorage.GlobalTradeFeeParams memory feeParams = _getMultiCollatDiamond()
            .getGlobalTradeFeeParams();

        if (_orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE) {
            uint256 totalLiqCollateralFeeP = _getMultiCollatDiamond().pairTotalLiqCollateralFeeP(
                _pairIndex
            );
            tradeFees.totalFeeCollateral =
                (_collateralAmount * totalLiqCollateralFeeP) /
                ConstantsUtils.P_10 /
                100;
        } else {
            tradeFees.totalFeeCollateral = getTotalTradeFeesCollateral(
                _collateralIndex,
                _trader,
                _pairIndex,
                _positionSizeCollateral
            );
        }

        address referrer = _getMultiCollatDiamond().getTraderActiveReferrer(_trader);
        uint256 referralFeeCollateral = (tradeFees.totalFeeCollateral * feeParams.referralFeeP) /
            1e3 /
            100;
        tradeFees.referralFeeCollateral = referrer != address(0)
            ? (referralFeeCollateral * _getMultiCollatDiamond().getReferrerFeeProgressP(referrer)) /
                ConstantsUtils.P_10 /
                100
            : 0;
        uint256 missingReferralFeeCollateral = referralFeeCollateral -
            tradeFees.referralFeeCollateral;

        tradeFees.govFeeCollateral =
            ((tradeFees.totalFeeCollateral * feeParams.govFeeP) / 1e3 / 100) +
            (missingReferralFeeCollateral / 2);

        uint256 triggerOrderFeeCollateral = (tradeFees.totalFeeCollateral *
            feeParams.triggerOrderFeeP) /
            1e3 /
            100;
        tradeFees.triggerOrderFeeCollateral = ConstantsUtils.isOrderTypeMarket(_orderType)
            ? 0
            : triggerOrderFeeCollateral;

        tradeFees.llpTokenFeeCollateral =
            (tradeFees.totalFeeCollateral * feeParams.llpTokenFeeP) /
            1e3 /
            100;
    }

    function getMinGovFeeCollateral(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex
    ) public view returns (uint256) {
        uint256 totalFeeCollateral = getTotalTradeFeesCollateral(
            _collateralIndex,
            _trader,
            _pairIndex,
            0 // position size is 0 so it will use the minimum pos
        ) / 2; // charge fee on min pos / 2
        return
            (totalFeeCollateral * _getMultiCollatDiamond().getGlobalTradeFeeParams().govFeeP) /
            1e3 /
            100;
    }

    /**
     * @dev Returns borrowingProvider contract
     */
    function getBorrowingProvider(
        uint8 _collateralIndex
    ) public view returns (IJavBorrowingProvider) {
        return
            IJavBorrowingProvider(_getMultiCollatDiamond().getBorrowingProvider(_collateralIndex));
    }

    // Transfers

    /**
     * @dev Transfers collateral from trader
     * @param _collateralIndex index of the collateral
     * @param _from sending address
     * @param _amountCollateral amount of collateral to receive (collateral precision)
     */
    function transferCollateralFrom(
        uint8 _collateralIndex,
        address _from,
        uint256 _amountCollateral
    ) public {
        if (_amountCollateral > 0) {
            IERC20(_getMultiCollatDiamond().getCollateral(_collateralIndex).collateral)
                .safeTransferFrom(_from, address(this), _amountCollateral);
        }
    }

    /**
     * @dev Transfers collateral to trader
     * @param _collateralIndex index of the collateral
     * @param _to receiving address
     * @param _amountCollateral amount of collateral to transfer (collateral precision)
     */
    function transferCollateralTo(
        uint8 _collateralIndex,
        address _to,
        uint256 _amountCollateral
    ) internal {
        if (_amountCollateral > 0) {
            IERC20(_getMultiCollatDiamond().getCollateral(_collateralIndex).collateral)
                .safeTransfer(_to, _amountCollateral);
        }
    }

    /**
     * @dev Sends collateral to borrowing provider vault for negative pnl
     * @param _collateralIndex collateral index
     * @param _amountCollateral amount of collateral to send to vault (collateral precision)
     * @param _trader trader address
     */
    function _sendCollateralToVault(
        uint8 _collateralIndex,
        uint256 _amountCollateral,
        address _trader
    ) private {
        getBorrowingProvider(_collateralIndex).receiveAssets(
            _collateralIndex,
            _amountCollateral,
            _trader
        );
    }

    /**
     * @dev Handles pnl transfers when (fully or partially) closing a trade
     * @param _trade trade struct
     * @param _collateralSentToTrader total amount to send to trader (collateral precision)
     * @param _availableCollateralInDiamond part of _collateralSentToTrader available in diamond balance (collateral precision)
     */
    function handleTradePnl(
        ITradingStorage.Trade memory _trade,
        int256 _collateralSentToTrader,
        int256 _availableCollateralInDiamond,
        uint256 _borrowingFeeCollateral
    ) external returns (uint256 traderDebt) {
        if (_collateralSentToTrader > _availableCollateralInDiamond) {
            getBorrowingProvider(_trade.collateralIndex).sendAssets(
                _trade.collateralIndex,
                uint256(_collateralSentToTrader - _availableCollateralInDiamond),
                _trade.user
            );
            if (_availableCollateralInDiamond >= 0) {
                transferCollateralTo(
                    _trade.collateralIndex,
                    _trade.user,
                    uint256(_availableCollateralInDiamond)
                );
            } else {
                traderDebt = uint256(-_availableCollateralInDiamond);
            }
        } else {
            getBorrowingProvider(_trade.collateralIndex).receiveAssets(
                _trade.collateralIndex,
                uint256(_availableCollateralInDiamond - _collateralSentToTrader),
                _trade.user
            );
            if (_collateralSentToTrader >= 0) {
                transferCollateralTo(
                    _trade.collateralIndex,
                    _trade.user,
                    uint256(_collateralSentToTrader)
                );
            } else {
                traderDebt = uint256(-_collateralSentToTrader);
            }
        }

        emit ITradingProcessingUtils.BorrowingFeeCharged(
            _trade.user,
            _trade.collateralIndex,
            _borrowingFeeCollateral
        );
    }

    // Fees

    /**
     * @dev Updates a trader's fee tiers points based on his trade size
     * @param _collateralIndex collateral index
     * @param _trader address of trader
     * @param _positionSizeCollateral position size in collateral tokens (collateral precision)
     * @param _pairIndex index of pair
     */
    function updateFeeTierPoints(
        uint8 _collateralIndex,
        address _trader,
        uint256 _pairIndex,
        uint256 _positionSizeCollateral
    ) public {
        uint256 usdNormalizedPositionSize = _getMultiCollatDiamond().getUsdNormalizedValue(
            _collateralIndex,
            _positionSizeCollateral
        );
        _getMultiCollatDiamond().updateTraderPoints(_trader, usdNormalizedPositionSize, _pairIndex);
    }

    /**
     * @dev Distributes fee to borrowing provider
     * @param _collateralIndex index of collateral
     * @param _trader address of trader
     * @param _valueCollateral fee in collateral tokens (collateral precision)
     */
    function distributeVaultFeeCollateral(
        uint8 _collateralIndex,
        address _trader,
        uint256 _valueCollateral
    ) internal {
        getBorrowingProvider(_collateralIndex).distributeReward(_collateralIndex, _valueCollateral);
        emit ITradingCommonUtils.BorrowingProviderFeeCharged(
            _trader,
            _collateralIndex,
            _valueCollateral
        );
    }

    /**
     * @dev Distributes gov fees exact amount
     * @param _collateralIndex index of collateral
     * @param _trader address of trader
     * @param _govFeeCollateral position size in collateral tokens (collateral precision)
     */
    function distributeExactGovFeeCollateral(
        uint8 _collateralIndex,
        address _trader,
        uint256 _govFeeCollateral
    ) public {
        TradingProcessingUtils._getStorage().pendingGovFees[_collateralIndex] += _govFeeCollateral;
        emit ITradingCommonUtils.GovFeeCharged(_trader, _collateralIndex, _govFeeCollateral);
    }

    /**
     * @dev Distribute staking rewards
     * @param _collateralIndex collateral index
     * @param _trader trader address
     * @param _amountCollateral amount of collateral tokens to distribute (collateral precision)
     */
    function distributeStakingReward(
        uint8 _collateralIndex,
        address _trader,
        uint256 _amountCollateral
    ) public {
        address collateral = _getMultiCollatDiamond().getCollateral(_collateralIndex).collateral;
        address rewardsDistributor = AddressStoreUtils.getAddresses().rewardsDistributor;
        address[] memory _tokens = new address[](1);
        _tokens[0] = collateral;

        IERC20(collateral).safeTransfer(rewardsDistributor, _amountCollateral);

        IRewardsDistributor(rewardsDistributor).distributeRewards(_tokens);
        emit ITradingCommonUtils.RewardsFeeCharged(_trader, _collateralIndex, _amountCollateral);
    }

    /**
     * @dev Distributes trigger fee in GNS tokens
     * @param _trader address of trader
     * @param _collateralIndex index of collateral
     * @param _triggerFeeCollateral trigger fee in collateral tokens (collateral precision)
     */
    function _distributeTriggerFee(
        address _trader,
        uint8 _collateralIndex,
        uint256 _triggerFeeCollateral
    ) internal {
        _getMultiCollatDiamond().distributeTriggerReward(_triggerFeeCollateral, _collateralIndex);

        emit ITradingCommonUtils.TriggerFeeCharged(
            _trader,
            _collateralIndex,
            _triggerFeeCollateral
        );
    }

    /**
     * @dev Distributes opening fees for trade and returns the trade fees charged in collateral tokens
     * @param _trade trade struct
     * @param _positionSizeCollateral position size in collateral tokens (collateral precision)
     * @param _orderType trade order type
     */
    function processFees(
        ITradingStorage.Trade memory _trade,
        uint256 _positionSizeCollateral,
        ITradingStorage.PendingOrderType _orderType
    ) external returns (uint256) {
        // 1. Before charging any fee, re-calculate current trader fee tier cache
        updateFeeTierPoints(
            _trade.collateralIndex,
            _trade.user,
            _trade.pairIndex,
            _positionSizeCollateral
        );

        // 2. Calculate all fees
        IPairsStorage.TradeFees memory tradeFees = getTradeFeesCollateral(
            _trade.collateralIndex,
            _trade.user,
            _trade.pairIndex,
            _trade.collateralAmount,
            _positionSizeCollateral,
            _orderType
        );

        // 3. Distribute fees only if trade collateral is enough to pay (due to min fee)
        if (_trade.collateralAmount >= tradeFees.totalFeeCollateral) {
            // 3.1 Distribute referral fee
            if (tradeFees.referralFeeCollateral > 0) {
                _distributeReferralFeeCollateral(
                    _trade.collateralIndex,
                    _trade.user,
                    _positionSizeCollateral,
                    tradeFees.referralFeeCollateral
                );
            }

            // 3.2 Distribute gov fee
            distributeExactGovFeeCollateral(
                _trade.collateralIndex,
                _trade.user,
                tradeFees.govFeeCollateral
            );

            //            // 3.3 Distribute trigger fee
            if (tradeFees.triggerOrderFeeCollateral > 0) {
                _distributeTriggerFee(
                    _trade.user,
                    _trade.collateralIndex,
                    tradeFees.triggerOrderFeeCollateral
                );
            }

            // 3.3 Distribute GToken fees
            distributeVaultFeeCollateral(
                _trade.collateralIndex,
                _trade.user,
                tradeFees.llpTokenFeeCollateral
            );
        }

        return tradeFees.totalFeeCollateral;
    }

    /**
     * @dev Distributes referral rewards and returns the amount charged in collateral tokens
     * @param _collateralIndex collateral index
     * @param _trader address of trader
     * @param _positionSizeCollateral position size in collateral tokens (collateral precision)
     * @param _referralFeeCollateral referral fee in collateral tokens (collateral precision)
     */
    function _distributeReferralFeeCollateral(
        uint8 _collateralIndex,
        address _trader,
        uint256 _positionSizeCollateral,
        uint256 _referralFeeCollateral
    ) internal {
        _getMultiCollatDiamond().distributeReferralReward(
            _trader,
            _getMultiCollatDiamond().getUsdNormalizedValue(
                _collateralIndex,
                _positionSizeCollateral
            ),
            _getMultiCollatDiamond().getUsdNormalizedValue(
                _collateralIndex,
                _referralFeeCollateral
            ),
            _getMultiCollatDiamond().getRewardsTokenPriceUsd()
        );

        emit ITradingCommonUtils.ReferralFeeCharged(
            _trader,
            _collateralIndex,
            _referralFeeCollateral
        );
    }

    // Open interests

    /**
     * @dev Update protocol open interest (any amount)
     * @dev CAREFUL: this will reset the trade's borrowing fees to 0 when _open = true
     * @param _trade trade struct
     * @param _positionSizeCollateral position size in collateral tokens (collateral precision)
     * @param _open whether it corresponds to a trade opening or closing
     * @param _isPnlPositive whether it corresponds to a positive pnl trade (only relevant when _open = false)
     */
    function updateOi(
        ITradingStorage.Trade memory _trade,
        uint256 _positionSizeCollateral,
        bool _open,
        bool _isPnlPositive
    ) public {
        _getMultiCollatDiamond().handleTradeBorrowingCallback(
            _trade.collateralIndex,
            _trade.user,
            _trade.pairIndex,
            _trade.index,
            _positionSizeCollateral,
            _open,
            _trade.long
        );
        _getMultiCollatDiamond().addPriceImpactOpenInterest(
            _trade.user,
            _trade.index,
            _positionSizeCollateral,
            _open,
            _isPnlPositive
        );
    }

    /**
     * @dev Update protocol open interest (trade position size)
     * @dev CAREFUL: this will reset the trade's borrowing fees to 0 when _open = true
     * @param _trade trade struct
     * @param _open whether it corresponds to a trade opening or closing
     * @param _isPnlPositive whether it corresponds to a positive pnl trade (only relevant when _open = false)
     */
    function updateOiTrade(
        ITradingStorage.Trade memory _trade,
        bool _open,
        bool _isPnlPositive
    ) external {
        updateOi(
            _trade,
            getPositionSizeCollateral(_trade.collateralAmount, _trade.leverage),
            _open,
            _isPnlPositive
        );
    }

    /**
     * @dev Handles OI delta for an existing trade (for trade updates)
     * @param _trade trade struct
     * @param _newPositionSizeCollateral new position size in collateral tokens (collateral precision)
     * @param _isPnlPositive whether it corresponds to a positive pnl trade (only relevant when closing)
     */
    function handleOiDelta(
        ITradingStorage.Trade memory _trade,
        uint256 _newPositionSizeCollateral,
        bool _isPnlPositive
    ) external {
        uint256 existingPositionSizeCollateral = getPositionSizeCollateral(
            _trade.collateralAmount,
            _trade.leverage
        );

        if (_newPositionSizeCollateral > existingPositionSizeCollateral) {
            updateOi(
                _trade,
                _newPositionSizeCollateral - existingPositionSizeCollateral,
                true,
                _isPnlPositive
            );
        } else if (_newPositionSizeCollateral < existingPositionSizeCollateral) {
            updateOi(
                _trade,
                existingPositionSizeCollateral - _newPositionSizeCollateral,
                false,
                _isPnlPositive
            );
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() private view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }
}
