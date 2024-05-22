// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/trade/IJavMultiCollatDiamond.sol";
import "../../interfaces/IWDFI.sol";
import "./StorageUtils.sol";
import "./PackingUtils.sol";
import "./ChainUtils.sol";

/**
 * @custom:version 8
 * @dev GNSTradingInteractions facet internal library
 */

library TradingInteractionsUtils {
    using PackingUtils for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e10;
    uint256 private constant MAX_SL_P = 75; // -75% PNL
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
     * @dev Modifier to prevent calling function from delegated action
     */
    modifier notDelegatedAction() {
        if (_getStorage().senderOverride != address(0))
            revert ITradingInteractionsUtils.DelegatedActionNotAllowed();
        _;
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function initializeTrading(
        uint16 _marketOrdersTimeoutBlocks,
        address[] memory _usersByPassTriggerLink
    ) internal {
        updateMarketOrdersTimeoutBlocks(_marketOrdersTimeoutBlocks);

        bool[] memory shouldByPass = new bool[](_usersByPassTriggerLink.length);
        for (uint256 i = 0; i < _usersByPassTriggerLink.length; i++) {
            shouldByPass[i] = true;
        }
        updateByPassTriggerLink(_usersByPassTriggerLink, shouldByPass);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateMarketOrdersTimeoutBlocks(uint16 _valueBlocks) internal {
        if (_valueBlocks == 0) revert IGeneralErrors.ZeroValue();

        _getStorage().marketOrdersTimeoutBlocks = _valueBlocks;

        emit ITradingInteractionsUtils.MarketOrdersTimeoutBlocksUpdated(_valueBlocks);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateByPassTriggerLink(
        address[] memory _users,
        bool[] memory _shouldByPass
    ) internal {
        ITradingInteractions.TradingInteractionsStorage storage s = _getStorage();

        if (_users.length != _shouldByPass.length) revert IGeneralErrors.WrongLength();

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            bool value = _shouldByPass[i];

            s.byPassTriggerLink[user] = value;

            emit ITradingInteractionsUtils.ByPassTriggerLinkUpdated(user, value);
        }
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function setTradingDelegate(address _delegate) internal {
        if (_delegate == address(0)) revert IGeneralErrors.ZeroAddress();
        _getStorage().delegations[msg.sender] = _delegate;
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function removeTradingDelegate() internal {
        delete _getStorage().delegations[msg.sender];
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function delegatedTradingAction(
        address _trader,
        bytes calldata _callData
    ) internal notDelegatedAction returns (bytes memory) {
        ITradingInteractions.TradingInteractionsStorage storage s = _getStorage();

        if (s.delegations[_trader] != msg.sender)
            revert ITradingInteractionsUtils.DelegateNotApproved();

        s.senderOverride = _trader;
        (bool success, bytes memory result) = address(this).delegatecall(_callData);

        if (!success) {
            if (result.length < 4) revert(); // not a custom error (4 byte signature) or require() message

            assembly {
                let len := mload(result)
                revert(add(result, 0x20), len)
            }
        }

        s.senderOverride = address(0);

        return result;
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function openTrade(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer
    ) internal tradingActivated {
        _openTrade(_trade, _maxSlippageP, _referrer, false);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function openTradeNative(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer
    ) internal tradingActivated notDelegatedAction {
        _trade.collateralAmount = _wrapNativeToken(_trade.collateralIndex);

        _openTrade(_trade, _maxSlippageP, _referrer, true);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function closeTradeMarket(uint32 _index) internal tradingActivatedOrCloseOnly {
        address sender = _msgSender();

        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(sender, _index);
        if (
            _getMultiCollatDiamond().getTradePendingOrderBlock(
                ITradingStorage.Id({user: t.user, index: t.index}),
                ITradingStorage.PendingOrderType.MARKET_CLOSE
            ) > 0
        ) revert ITradingInteractionsUtils.AlreadyBeingMarketClosed();

        ITradingStorage.PendingOrder memory pendingOrder;
        pendingOrder.trade.user = t.user;
        pendingOrder.trade.index = t.index;
        pendingOrder.trade.pairIndex = t.pairIndex;
        pendingOrder.user = sender;
        pendingOrder.orderType = ITradingStorage.PendingOrderType.MARKET_CLOSE;

        pendingOrder = _getMultiCollatDiamond().storePendingOrder(pendingOrder);
        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: pendingOrder.user,
            index: pendingOrder.index
        });

        _getMultiCollatDiamond().getPrice(
            t.collateralIndex,
            t.pairIndex,
            orderId,
            pendingOrder.orderType,
            _getPositionSizeCollateral(t.collateralAmount, t.leverage),
            ChainUtils.getBlockNumber()
        );

        emit ITradingInteractionsUtils.MarketOrderInitiated(orderId, sender, t.pairIndex, false);
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
        address sender = _msgSender();
        ITradingStorage.Trade memory o = _getMultiCollatDiamond().getTrade(sender, _index);

        _checkNoPendingTrigger(
            ITradingStorage.Id({user: o.user, index: o.index}),
            _getMultiCollatDiamond().getPendingOpenOrderType(o.tradeType)
        );

        _getMultiCollatDiamond().updateOpenOrderDetails(
            ITradingStorage.Id({user: o.user, index: o.index}),
            _openPrice,
            _tp,
            _sl,
            _maxSlippageP
        );

        emit ITradingInteractionsUtils.OpenLimitUpdated(
            sender,
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
        address sender = _msgSender();
        ITradingStorage.Trade memory o = _getMultiCollatDiamond().getTrade(sender, _index);
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({user: o.user, index: o.index});

        if (o.tradeType == ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();

        _checkNoPendingTrigger(
            tradeId,
            _getMultiCollatDiamond().getPendingOpenOrderType(o.tradeType)
        );

        _getMultiCollatDiamond().closeTrade(tradeId);

        _transferCollateralToTrader(o.collateralIndex, sender, o.collateralAmount);

        emit ITradingInteractionsUtils.OpenLimitCanceled(sender, o.pairIndex, _index);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateTp(uint32 _index, uint64 _newTp) internal tradingActivated {
        address sender = _msgSender();

        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(sender, _index);
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({user: t.user, index: t.index});

        _checkNoPendingTrigger(tradeId, ITradingStorage.PendingOrderType.TP_CLOSE);

        _getMultiCollatDiamond().updateTradeTp(tradeId, _newTp);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function updateSl(uint32 _index, uint64 _newSl) internal tradingActivated {
        address sender = _msgSender();

        ITradingStorage.Trade memory t = _getMultiCollatDiamond().getTrade(sender, _index);
        ITradingStorage.Id memory tradeId = ITradingStorage.Id({user: t.user, index: t.index});

        _checkNoPendingTrigger(tradeId, ITradingStorage.PendingOrderType.SL_CLOSE);

        _getMultiCollatDiamond().updateTradeSl(tradeId, _newSl);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function triggerOrder(uint256 _packed) internal notDelegatedAction {
        (uint8 _orderType, address _trader, uint32 _index) = _packed.unpackTriggerOrder();

        ITradingStorage.PendingOrderType orderType = ITradingStorage.PendingOrderType(_orderType);

        if (
            orderType == ITradingStorage.PendingOrderType.MARKET_OPEN ||
            orderType == ITradingStorage.PendingOrderType.MARKET_CLOSE
        ) revert ITradingInteractionsUtils.WrongOrderType();

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

        if (orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE && t.sl > 0) {
            uint256 liqPrice = _getMultiCollatDiamond().getTradeLiquidationPrice(
                IBorrowingFees.LiqPriceInput(
                    t.collateralIndex,
                    t.user,
                    t.pairIndex,
                    t.index,
                    t.openPrice,
                    t.long,
                    t.collateralAmount,
                    t.leverage
                )
            );

            // If liq price not closer than SL, turn order into a SL order
            if ((t.long && liqPrice <= t.sl) || (!t.long && liqPrice >= t.sl)) {
                orderType = ITradingStorage.PendingOrderType.SL_CLOSE;
            }
        }

        _checkNoPendingTrigger(ITradingStorage.Id({user: t.user, index: t.index}), orderType);

        address sender = _msgSender();
        bool byPassesLinkCost = _getStorage().byPassTriggerLink[sender];

        uint256 positionSizeCollateral = _getPositionSizeCollateral(t.collateralAmount, t.leverage);

        if (isOpenLimit) {
            uint256 leveragedPosUsd = _getMultiCollatDiamond().getUsdNormalizedValue(
                t.collateralIndex,
                positionSizeCollateral
            );
            (uint256 priceImpactP, ) = _getMultiCollatDiamond().getTradePriceImpact(
                0,
                t.pairIndex,
                t.long,
                leveragedPosUsd
            );

            if ((priceImpactP * t.leverage) / 1e3 > MAX_OPEN_NEGATIVE_PNL_P)
                revert ITradingInteractionsUtils.PriceImpactTooHigh();
        }

        if (!byPassesLinkCost) {
            IERC20(_getMultiCollatDiamond().getChainlinkToken()).safeTransferFrom(
                sender,
                address(this),
                _getMultiCollatDiamond().getLinkFee(
                    t.collateralIndex,
                    t.pairIndex,
                    positionSizeCollateral
                )
            );
        }

        ITradingStorage.PendingOrder memory pendingOrder;
        pendingOrder.trade.user = t.user;
        pendingOrder.trade.index = t.index;
        pendingOrder.trade.pairIndex = t.pairIndex;
        pendingOrder.user = sender;
        pendingOrder.orderType = orderType;

        pendingOrder = _getMultiCollatDiamond().storePendingOrder(pendingOrder);

        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: pendingOrder.user,
            index: pendingOrder.index
        });

        _getPriceTriggerOrder(t, orderId, orderType, byPassesLinkCost ? 0 : positionSizeCollateral);

        emit ITradingInteractionsUtils.TriggerOrderInitiated(
            orderId,
            _trader,
            t.pairIndex,
            byPassesLinkCost
        );
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function openTradeMarketTimeout(
        ITradingStorage.Id memory _orderId
    ) internal tradingActivatedOrCloseOnly {
        address sender = _msgSender();

        ITradingStorage.PendingOrder memory o = _getMultiCollatDiamond().getPendingOrder(_orderId);
        ITradingStorage.Trade memory t = o.trade;

        if (!o.isOpen) revert ITradingInteractionsUtils.NoOrder();

        if (ChainUtils.getBlockNumber() < o.createdBlock + _getStorage().marketOrdersTimeoutBlocks)
            revert ITradingInteractionsUtils.WaitTimeout();

        if (t.user != sender) revert ITradingInteractionsUtils.NotYourOrder();

        if (o.orderType != ITradingStorage.PendingOrderType.MARKET_OPEN)
            revert ITradingInteractionsUtils.WrongOrderType();

        _getMultiCollatDiamond().closePendingOrder(_orderId);

        _transferCollateralToTrader(t.collateralIndex, sender, t.collateralAmount);

        emit ITradingInteractionsUtils.ChainlinkCallbackTimeout(_orderId, t.pairIndex);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function closeTradeMarketTimeout(
        ITradingStorage.Id memory _orderId
    ) internal tradingActivatedOrCloseOnly {
        address sender = _msgSender();

        ITradingStorage.PendingOrder memory o = _getMultiCollatDiamond().getPendingOrder(_orderId);
        ITradingStorage.Trade memory t = o.trade;

        if (!o.isOpen) revert ITradingInteractionsUtils.NoOrder();

        if (ChainUtils.getBlockNumber() < o.createdBlock + _getStorage().marketOrdersTimeoutBlocks)
            revert ITradingInteractionsUtils.WaitTimeout();

        if (t.user != sender) revert ITradingInteractionsUtils.NotYourOrder();

        if (o.orderType != ITradingStorage.PendingOrderType.MARKET_CLOSE)
            revert ITradingInteractionsUtils.WrongOrderType();

        _getMultiCollatDiamond().closePendingOrder(_orderId);

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSelector(ITradingInteractionsUtils.closeTradeMarket.selector, t.index)
        );

        if (!success) {
            emit ITradingInteractionsUtils.CouldNotCloseTrade(sender, t.pairIndex, t.index);
        }

        emit ITradingInteractionsUtils.ChainlinkCallbackTimeout(_orderId, t.pairIndex);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function getWrappedNativeToken() internal view returns (address) {
        return ChainUtils.getWrappedNativeToken();
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function isWrappedNativeToken(address _token) internal view returns (bool) {
        return ChainUtils.isWrappedNativeToken(_token);
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function getTradingDelegate(address _trader) internal view returns (address) {
        return _getStorage().delegations[_trader];
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function getMarketOrdersTimeoutBlocks() internal view returns (uint16) {
        return _getStorage().marketOrdersTimeoutBlocks;
    }

    /**
     * @dev Check ITradingInteractionsUtils interface for documentation
     */
    function getByPassTriggerLink(address _user) internal view returns (bool) {
        return _getStorage().byPassTriggerLink[_user];
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
     * @dev Private function for openTrade and openTradeNative
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
        address sender = _msgSender();
        _trade.user = sender;

        uint256 positionSizeCollateral = _getPositionSizeCollateral(
            _trade.collateralAmount,
            _trade.leverage
        );
        uint256 positionSizeUsd = _getMultiCollatDiamond().getUsdNormalizedValue(
            _trade.collateralIndex,
            positionSizeCollateral
        );

        if (
            _getMultiCollatDiamond().getPairOiCollateral(
                _trade.collateralIndex,
                _trade.pairIndex,
                _trade.long
            ) +
                positionSizeCollateral >
            _getMultiCollatDiamond().getPairMaxOiCollateral(
                _trade.collateralIndex,
                _trade.pairIndex
            )
        ) revert ITradingInteractionsUtils.AbovePairMaxOi();

        if (
            !_getMultiCollatDiamond().withinMaxBorrowingGroupOi(
                _trade.collateralIndex,
                _trade.pairIndex,
                _trade.long,
                positionSizeCollateral
            )
        ) revert ITradingInteractionsUtils.AboveGroupMaxOi();

        if (positionSizeUsd < _getMultiCollatDiamond().pairMinPositionSizeUsd(_trade.pairIndex))
            revert ITradingInteractionsUtils.BelowMinPositionSizeUsd();

        if (
            _trade.leverage < _getMultiCollatDiamond().pairMinLeverage(_trade.pairIndex) * 1e3 ||
            _trade.leverage > _getMultiCollatDiamond().pairMaxLeverage(_trade.pairIndex) * 1e3
        ) revert ITradingInteractionsUtils.WrongLeverage();

        (uint256 priceImpactP, ) = _getMultiCollatDiamond().getTradePriceImpact(
            0,
            _trade.pairIndex,
            _trade.long,
            positionSizeUsd
        );

        if ((priceImpactP * _trade.leverage) / 1e3 > MAX_OPEN_NEGATIVE_PNL_P)
            revert ITradingInteractionsUtils.PriceImpactTooHigh();

        if (!_isNative)
            _receiveCollateralFromTrader(_trade.collateralIndex, sender, _trade.collateralAmount);

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

            pendingOrder = _getMultiCollatDiamond().storePendingOrder(pendingOrder);

            ITradingStorage.Id memory orderId = ITradingStorage.Id({
                user: pendingOrder.user,
                index: pendingOrder.index
            });

            _getMultiCollatDiamond().getPrice(
                _trade.collateralIndex,
                _trade.pairIndex,
                orderId,
                pendingOrder.orderType,
                positionSizeCollateral,
                ChainUtils.getBlockNumber()
            );

            emit ITradingInteractionsUtils.MarketOrderInitiated(
                orderId,
                sender,
                _trade.pairIndex,
                true
            );
        }

        if (_referrer != address(0)) {
            _getMultiCollatDiamond().registerPotentialReferrer(sender, _referrer);
        }
    }

    /**
     * @dev Revert if there is an active pending order for the trade
     * @param _tradeId trade id
     * @param _orderType order type
     */
    function _checkNoPendingTrigger(
        ITradingStorage.Id memory _tradeId,
        ITradingStorage.PendingOrderType _orderType
    ) internal view {
        if (
            _getMultiCollatDiamond().hasActiveOrder(
                _getMultiCollatDiamond().getTradePendingOrderBlock(_tradeId, _orderType)
            )
        ) revert ITradingInteractionsUtils.PendingTrigger();
    }

    /**
     * @dev Initiate price aggregator request for trigger order
     * @param _trade trade
     * @param _orderId order id
     * @param _orderType order type
     * @param _positionSizeCollateral position size in collateral tokens (collateral precision)
     */
    function _getPriceTriggerOrder(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.Id memory _orderId,
        ITradingStorage.PendingOrderType _orderType,
        uint256 _positionSizeCollateral // collateral precision
    ) internal {
        ITradingStorage.TradeInfo memory tradeInfo = _getMultiCollatDiamond().getTradeInfo(
            _trade.user,
            _trade.index
        );

        _getMultiCollatDiamond().getPrice(
            _trade.collateralIndex,
            _trade.pairIndex,
            _orderId,
            _orderType,
            _positionSizeCollateral,
            _orderType == ITradingStorage.PendingOrderType.SL_CLOSE
                ? tradeInfo.slLastUpdatedBlock
                : _orderType == ITradingStorage.PendingOrderType.TP_CLOSE
                ? tradeInfo.tpLastUpdatedBlock
                : tradeInfo.createdBlock
        );
    }

    /**
     * @dev Receives native token and sends back wrapped token to user
     * @param _collateralIndex index of the collateral
     */
    function _wrapNativeToken(uint8 _collateralIndex) internal returns (uint120) {
        address collateral = _getMultiCollatDiamond().getCollateral(_collateralIndex).collateral;
        uint256 nativeValue = msg.value;

        if (nativeValue == 0) {
            revert IGeneralErrors.ZeroValue();
        }

        if (nativeValue > type(uint120).max) {
            revert IGeneralErrors.Overflow();
        }

        if (!ChainUtils.isWrappedNativeToken(collateral)) {
            revert ITradingInteractionsUtils.NotWrappedNativeToken();
        }

        IWDFI(collateral).deposit{value: nativeValue}();

        emit ITradingInteractionsUtils.NativeTokenWrapped(msg.sender, nativeValue);

        return uint120(nativeValue);
    }

    /**
     * @dev Returns the caller of the transaction (overriden by trader address if delegatedAction is called)
     */
    function _msgSender() internal view returns (address) {
        address senderOverride = _getStorage().senderOverride;
        if (senderOverride == address(0)) {
            return msg.sender;
        } else {
            return senderOverride;
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
