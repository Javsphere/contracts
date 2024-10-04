// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/leverageX/IJavMultiCollatDiamond.sol";
import "../../interfaces/IRewardsDistributor.sol";

import "./AddressStoreUtils.sol";
import "./StorageUtils.sol";
import "./PackingUtils.sol";
import "./TradingCommonUtils.sol";
import "./updateLeverage/UpdateLeverageUtils.sol";
import "./updatePositionSize/UpdatePositionSizeUtils.sol";

/**
 * @custom:version 8
 * @dev JavTradingInteractions facet internal library
 */

library TradingInteractionsUtils {
    using PackingUtils for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e10;
    uint256 private constant MAX_OPEN_NEGATIVE_PNL_P = 40 * 1e10; // -40% PNL

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
     * @dev Modifier to perform price update
     */
    modifier onlyWithPriceUpdate(bytes[][] calldata _priceUpdate) {
        require(_priceUpdate.length == 2, "JavTradingInteractions: invalid priceUpdate data");
        _getMultiCollatDiamond().updatePrices{value: msg.value}(_priceUpdate, msg.sender);
        _;
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function openTrade(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer,
        bytes[][] calldata _priceUpdate
    ) internal tradingActivated onlyWithPriceUpdate(_priceUpdate) {
        _openTrade(_trade, _maxSlippageP, _referrer, false);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateMaxClosingSlippageP(
        uint32 _index,
        uint16 _maxClosingSlippageP
    ) internal tradingActivatedOrCloseOnly {
        _getMultiCollatDiamond().updateTradeMaxClosingSlippageP(
            ITradingStorage.Id(msg.sender, _index),
            _maxClosingSlippageP
        );
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function closeTradeMarket(
        uint32 _index,
        bytes[][] calldata _priceUpdate
    ) internal tradingActivatedOrCloseOnly onlyWithPriceUpdate(_priceUpdate) {
        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(msg.sender, _index);

        ITradingStorage.PendingOrder memory pendingOrder;
        pendingOrder.trade.user = t.user;
        pendingOrder.trade.index = t.index;
        pendingOrder.trade.pairIndex = t.pairIndex;
        pendingOrder.user = msg.sender;
        pendingOrder.orderType = ITradingStorage.PendingOrderType.MARKET_CLOSE;
        pendingOrder.price = uint64(_getMultiCollatDiamond().getPrice(t.pairIndex));

        _getMultiCollatDiamond().closeTradeMarketOrder(pendingOrder);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateOpenOrder(
        uint32 _index,
        uint64 _openPrice, // PRECISION
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) internal tradingActivated {
        ITradingStorage.Trade memory o = _getMultiCollatDiamond().getTrade(msg.sender, _index);

        _getMultiCollatDiamond().updateOpenOrderDetails(
            ITradingStorage.Id({user: o.user, index: o.index}),
            _openPrice,
            _tp,
            _sl,
            _maxSlippageP
        );

        emit ITradingInteractionsUtils.OpenLimitUpdated(
            msg.sender,
            o.pairIndex,
            _index,
            _openPrice,
            _tp,
            _sl,
            _maxSlippageP
        );
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function cancelOpenOrder(uint32 _index) internal tradingActivatedOrCloseOnly {
        ITradingStorage.Trade memory o = _getMultiCollatDiamond().getTrade(msg.sender, _index);
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({user: o.user, index: o.index});

        if (o.tradeType == ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();

        _getMultiCollatDiamond().closeTrade(tradeId);

        _transferCollateralToTrader(o.collateralIndex, msg.sender, o.collateralAmount);

        emit ITradingInteractionsUtils.OpenLimitCanceled(msg.sender, o.pairIndex, _index);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateTp(uint32 _index, uint64 _newTp) internal tradingActivated {
        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(msg.sender, _index);
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({user: t.user, index: t.index});

        _getMultiCollatDiamond().updateTradeTp(tradeId, _newTp);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateSl(uint32 _index, uint64 _newSl) internal tradingActivated {
        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(msg.sender, _index);
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({user: t.user, index: t.index});

        _getMultiCollatDiamond().updateTradeSl(tradeId, _newSl);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateLeverage(
        uint32 _index,
        uint24 _newLeverage,
        bytes[][] calldata _priceUpdate
    ) internal tradingActivated onlyWithPriceUpdate(_priceUpdate) {
        UpdateLeverageUtils.updateLeverage(
            IUpdateLeverage.UpdateLeverageInput(msg.sender, _index, _newLeverage)
        );
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function increasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        uint64 _expectedPrice,
        uint16 _maxSlippageP,
        bytes[][] calldata _priceUpdate
    ) internal tradingActivated onlyWithPriceUpdate(_priceUpdate) {
        UpdatePositionSizeUtils.increasePositionSize(
            IUpdatePositionSize.IncreasePositionSizeInput(
                msg.sender,
                _index,
                _collateralDelta,
                _leverageDelta,
                _expectedPrice,
                _maxSlippageP
            )
        );
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function decreasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        bytes[][] calldata _priceUpdate
    ) internal tradingActivatedOrCloseOnly onlyWithPriceUpdate(_priceUpdate) {
        UpdatePositionSizeUtils.decreasePositionSize(
            IUpdatePositionSize.DecreasePositionSizeInput(
                msg.sender,
                _index,
                _collateralDelta,
                _leverageDelta
            )
        );
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function triggerOrder(
        uint256 _packed,
        bytes[][] calldata _priceUpdate
    ) internal onlyWithPriceUpdate(_priceUpdate) {
        (uint8 _orderType, address _trader, uint32 _index) = _packed.unpackTriggerOrder();

        ITradingStorage.PendingOrderType orderType = ITradingStorage.PendingOrderType(_orderType);

        if (ConstantsUtils.isOrderTypeMarket(orderType)) revert IGeneralErrors.WrongOrderType();

        bool isOpenLimit = orderType == ITradingStorage.PendingOrderType.LIMIT_OPEN ||
            orderType == ITradingStorage.PendingOrderType.STOP_OPEN;

        ITradingStorage.TradingActivated activated = _getMultiCollatDiamond().getTradingActivated();
        if (
            (isOpenLimit && activated != ITradingStorage.TradingActivated.ACTIVATED) ||
            (!isOpenLimit && activated == ITradingStorage.TradingActivated.PAUSED)
        ) {
            revert IGeneralErrors.GeneralPaused();
        }

        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(_trader, _index);
        if (!t.isOpen) revert ITradingInteractionsUtils.NoTrade();

        address sender = msg.sender;

        uint256 positionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
            t.collateralAmount,
            t.leverage
        );

        if (isOpenLimit) {
            (uint256 priceImpactP, ) = TradingCommonUtils.getTradeOpeningPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(t, 0, 0, positionSizeCollateral)
            );

            if ((priceImpactP * t.leverage) / 1e3 > ConstantsUtils.MAX_OPEN_NEGATIVE_PNL_P)
                revert ITradingInteractionsUtils.PriceImpactTooHigh();
        }

        ITradingStorage.PendingOrder memory pendingOrder;
        pendingOrder.trade.user = t.user;
        pendingOrder.trade.index = t.index;
        pendingOrder.trade.pairIndex = t.pairIndex;
        pendingOrder.user = sender;
        pendingOrder.orderType = orderType;
        pendingOrder.isOpen = t.isOpen;
        pendingOrder.price = uint64(_getMultiCollatDiamond().getPrice(t.pairIndex));

        if (
            orderType == ITradingStorage.PendingOrderType.LIMIT_OPEN ||
            orderType == ITradingStorage.PendingOrderType.STOP_OPEN
        ) {
            _getMultiCollatDiamond().executeTriggerOpenOrder(pendingOrder);
        } else {
            _getMultiCollatDiamond().executeTriggerCloseOrder(pendingOrder);
        }
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRADING_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (ITradingInteractions.TradingInteractionsStorage storage s)
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

    /**
     * @dev Internal function for openTrade and openTradeNative
     * @param _trade trade data
     * @param _maxSlippageP max slippage percentage (1e3 precision)
     * @param _referrer referrer address
     * @param _isNative if true we skip the collateral transfer from user to contract
     */
    function _openTrade(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer,
        bool _isNative
    ) internal {
        address sender = msg.sender;
        _trade.user = sender;
        _trade.__placeholder = 0;

        uint256 positionSizeCollateral = TradingCommonUtils.getPositionSizeCollateral(
            _trade.collateralAmount,
            _trade.leverage
        );
        uint256 positionSizeUsd = _getMultiCollatDiamond().getUsdNormalizedValue(
            _trade.collateralIndex,
            positionSizeCollateral
        );

        if (
            !TradingCommonUtils.isWithinExposureLimits(
                _trade.collateralIndex,
                _trade.pairIndex,
                _trade.long,
                positionSizeCollateral
            )
        ) revert ITradingInteractionsUtils.AboveExposureLimits();

        // Trade collateral usd value needs to be >= 5x min trade fee usd (collateral left after trade opened >= 80%)
        if (
            (positionSizeUsd * 1e3) / _trade.leverage <
            5 * _getMultiCollatDiamond().pairMinFeeUsd(_trade.pairIndex)
        ) revert ITradingInteractionsUtils.InsufficientCollateral();

        if (
            _trade.leverage < _getMultiCollatDiamond().pairMinLeverage(_trade.pairIndex) * 1e3 ||
            _trade.leverage > _getMultiCollatDiamond().pairMaxLeverage(_trade.pairIndex) * 1e3
        ) revert ITradingInteractionsUtils.WrongLeverage();

        (uint256 priceImpactP, ) = TradingCommonUtils.getTradeOpeningPriceImpact(
            ITradingCommonUtils.TradePriceImpactInput(_trade, 0, 0, positionSizeCollateral)
        );

        if ((priceImpactP * _trade.leverage) / 1e3 > ConstantsUtils.MAX_OPEN_NEGATIVE_PNL_P)
            revert ITradingInteractionsUtils.PriceImpactTooHigh();

        if (!_isNative)
            TradingCommonUtils.transferCollateralFrom(
                _trade.collateralIndex,
                sender,
                _trade.collateralAmount
            );

        if (_trade.tradeType != ITradingStorage.TradeType.TRADE) {
            ITradingStorage.TradeInfo memory tradeInfo;
            tradeInfo.maxSlippageP = _maxSlippageP;

            _trade = _getMultiCollatDiamond().storeTrade(_trade, tradeInfo);

            emit ITradingInteractionsUtils.OpenOrderPlaced(sender, _trade.pairIndex, _trade.index);
        } else {
            ITradingStorage.PendingOrder memory pendingOrder;
            pendingOrder.trade = _trade;
            pendingOrder.user = sender;
            pendingOrder.orderType = ITradingStorage.PendingOrderType.MARKET_OPEN;
            pendingOrder.maxSlippageP = _maxSlippageP;
            pendingOrder.price = uint64(_getMultiCollatDiamond().getPrice(_trade.pairIndex));

            _getMultiCollatDiamond().openTradeMarketOrder(pendingOrder);

            emit ITradingInteractionsUtils.MarketOrderInitiated(msg.sender, _trade.pairIndex, true);
        }

        if (_referrer != address(0)) {
            _getMultiCollatDiamond().registerPotentialReferrer(sender, _referrer);
        }
    }

    /**
     * @dev Receives collateral from trader
     * @param _collateralIndex index of the collateral
     * @param _from address from which to receive collateral
     * @param _amountCollateral amount of collateral to receive (collateral precision)
     */
    function _receiveCollateralFromTrader(
        uint8 _collateralIndex,
        address _from,
        uint256 _amountCollateral
    ) internal {
        IERC20(_getMultiCollatDiamond().getCollateral(_collateralIndex).collateral)
            .safeTransferFrom(_from, address(this), _amountCollateral);
    }

    /**
     * @dev Transfers collateral to trader
     * @param _collateralIndex index of the collateral
     * @param _to address to which to transfer collateral
     * @param _amountCollateral amount of collateral to transfer (collateral precision)
     */
    function _transferCollateralToTrader(
        uint8 _collateralIndex,
        address _to,
        uint256 _amountCollateral
    ) internal {
        IERC20(_getMultiCollatDiamond().getCollateral(_collateralIndex).collateral).safeTransfer(
            _to,
            _amountCollateral
        );
    }

    /**
     * @dev Returns position size of trade in collateral tokens, avoiding overflow from uint120 collateralAmount
     * @param _collateralAmount collateral of trade
     * @param _leverage leverage of trade (1e3)
     */
    function _getPositionSizeCollateral(
        uint120 _collateralAmount,
        uint24 _leverage
    ) internal pure returns (uint256) {
        return (uint256(_collateralAmount) * _leverage) / 1e3;
    }
}
