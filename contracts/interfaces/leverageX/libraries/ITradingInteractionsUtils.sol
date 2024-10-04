// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/ITradingInteractions.sol";
import "../types/ITradingStorage.sol";

/**
 * @custom:version 8
 * @dev Interface for JavTradingInteractions facet (inherits types and also contains functions, events, and custom errors)
 */
interface ITradingInteractionsUtils is ITradingInteractions {
    /**
     * @dev Opens a new trade/limit order/stop order
     * @param _trade the trade to be opened
     * @param _maxSlippageP the maximum allowed slippage % when open the trade (1e3 precision)
     * @param _referrer the address of the referrer (can only be set once for a trader)
     * @param _priceUpdate Array of price update data.
     */
    function openTrade(
        ITradingStorage.Trade memory _trade,
        uint16 _maxSlippageP,
        address _referrer,
        bytes[][] calldata _priceUpdate
    ) external payable;

    /**
     * @dev Updates existing trade's max closing slippage % for caller
     * @param _index index of trade
     * @param _maxSlippageP new max closing slippage % (1e3 precision)
     */
    function updateMaxClosingSlippageP(uint32 _index, uint16 _maxSlippageP) external;

    /**
     * @dev Closes an open trade (market order) for caller
     * @param _index the index of the trade of caller
     * @param _priceUpdate Array of price update data.
     */
    function closeTradeMarket(uint32 _index, bytes[][] calldata _priceUpdate) external payable;

    /**
     * @dev Updates an existing limit/stop order for caller
     * @param _index index of limit/stop order of caller
     * @param _triggerPrice new trigger price of limit/stop order (1e10 precision)
     * @param _tp new tp of limit/stop order (1e10 precision)
     * @param _sl new sl of limit/stop order (1e10 precision)
     * @param _maxSlippageP new max slippage % of limit/stop order (1e3 precision)
     */
    function updateOpenOrder(
        uint32 _index,
        uint64 _triggerPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) external;

    /**
     * @dev Cancels an open limit/stop order for caller
     * @param _index index of limit/stop order of caller
     */
    function cancelOpenOrder(uint32 _index) external;

    /**
     * @dev Updates the tp of an open trade for caller
     * @param _index index of open trade of caller
     * @param _newTp new tp of open trade (1e10 precision)
     */
    function updateTp(uint32 _index, uint64 _newTp) external;

    /**
     * @dev Updates the sl of an open trade for caller
     * @param _index index of open trade of caller
     * @param _newSl new sl of open trade (1e10 precision)
     */
    function updateSl(uint32 _index, uint64 _newSl) external;

    /**
     * @dev Update trade leverage
     * @param _index index of trade
     * @param _newLeverage new leverage (1e3)
     * @param _priceUpdate Array of price update data.
     */
    function updateLeverage(
        uint32 _index,
        uint24 _newLeverage,
        bytes[][] calldata _priceUpdate
    ) external payable;

    /**
     * @dev Increase trade position size
     * @param _index index of trade
     * @param _collateralDelta collateral to add (collateral precision)
     * @param _leverageDelta partial trade leverage (1e3)
     * @param _expectedPrice expected price of execution (1e10 precision)
     * @param _maxSlippageP max slippage % (1e3)
     * @param _priceUpdate Array of price update data.
     */
    function increasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        uint64 _expectedPrice,
        uint16 _maxSlippageP,
        bytes[][] calldata _priceUpdate
    ) external payable;

    /**
     * @dev Decrease trade position size
     * @param _index index of trade
     * @param _collateralDelta collateral to remove (collateral precision)
     * @param _leverageDelta leverage to reduce by (1e3)
     * @param _priceUpdate Array of price update data.
     */
    function decreasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        bytes[][] calldata _priceUpdate
    ) external payable;

    /**
     * @dev Initiates a new trigger order (for tp/sl/liq/limit/stop orders)
     * @param _packed the packed data of the trigger order (orderType, trader, index)
     * @param _priceUpdate Array of price update data.
     */
    function triggerOrder(uint256 _packed, bytes[][] calldata _priceUpdate) external payable;

    /**
     * @dev Emitted when a market order is initiated
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param open whether the market order is for opening or closing a trade
     */
    event MarketOrderInitiated(address indexed trader, uint16 indexed pairIndex, bool open);

    /**
     * @dev Emitted when a new limit/stop order is placed
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open limit order for caller
     */
    event OpenOrderPlaced(address indexed trader, uint16 indexed pairIndex, uint32 index);

    /**
     *
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open limit/stop order for caller
     * @param newPrice new trigger price (1e10 precision)
     * @param newTp new tp (1e10 precision)
     * @param newSl new sl (1e10 precision)
     * @param maxSlippageP new max slippage % (1e3 precision)
     */
    event OpenLimitUpdated(
        address indexed trader,
        uint16 indexed pairIndex,
        uint32 index,
        uint64 newPrice,
        uint64 newTp,
        uint64 newSl,
        uint64 maxSlippageP
    );

    /**
     * @dev Emitted when a limit/stop order is canceled (collateral sent back to trader)
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open limit/stop order for caller
     */
    event OpenLimitCanceled(address indexed trader, uint16 indexed pairIndex, uint32 index);

    /**
     * @dev Emitted when a pending market order is canceled due to timeout and new closeTradeMarket() call failed
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open trade for caller
     */
    event CouldNotCloseTrade(address indexed trader, uint16 indexed pairIndex, uint32 index);

    error NotWrappedNativeToken();
    error DelegateNotApproved();
    error PriceZero();
    error AboveExposureLimits();
    error AbovePairMaxOi();
    error AboveGroupMaxOi();
    error CollateralNotActive();
    error BelowMinPositionSizeUsd();
    error PriceImpactTooHigh();
    error NoTrade();
    error NoOrder();
    error AlreadyBeingMarketClosed();
    error WrongLeverage();
    error WrongTp();
    error WrongSl();
    error WaitTimeout();
    error PendingTrigger();
    error NoSl();
    error NoTp();
    error NotYourOrder();
    error DelegatedActionNotAllowed();
    error InsufficientCollateral();
}
