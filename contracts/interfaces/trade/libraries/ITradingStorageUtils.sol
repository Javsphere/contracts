// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/ITradingStorage.sol";

/**
 * @custom:version 8
 * @dev Interface for JavTradingStorage facet (inherits types and also contains functions, events, and custom errors)
 */
interface ITradingStorageUtils is ITradingStorage {
    /**
     * @dev Initializes the trading storage facet
     * @param _rewardsToken address of the rewards token
     * @param _rewardsDistributor address of the rewards distributor contract
     */
    function initializeTradingStorage(
        address _rewardsToken,
        address _rewardsDistributor,
        address _borrowingProvider,
        address[] memory _collaterals,
        uint8[] memory _collateralsIndexes
    ) external;

    /**
     * @dev Updates the trading activated state
     * @param _activated the new trading activated state
     */
    function updateTradingActivated(TradingActivated _activated) external;

    /**
     * @dev Adds a new supported collateral
     * @param _collateral the address of the collateral
     * @param _index index of the collateral
     */
    function addCollateral(address _collateral, uint8 _index) external;

    /**
     * @dev Toggles the active state of a supported collateral
     * @param _collateralIndex index of the collateral
     */
    function toggleCollateralActiveState(uint8 _collateralIndex) external;

    /**
     * @dev Update borrowing provider address
     * @param _borrowingProvider borrowing provider address
     */
    function updateBorrowingProvider(address _borrowingProvider) external;

    /**
     * @dev Update collateral approve
     * @param _collateralIndex index of collateral
     */
    function updateCollateralApprove(uint8 _collateralIndex) external;

    /**
     * @dev Stores a new trade (trade/limit/stop)
     * @param _trade trade to be stored
     * @param _tradeInfo trade info to be stored
     */
    function storeTrade(
        Trade memory _trade,
        TradeInfo memory _tradeInfo
    ) external returns (Trade memory);

    /**
     * @dev Updates an existing trade max closing slippage %
     * @param _tradeId id of the trade
     * @param _maxSlippageP new max slippage % (1e3 precision)
     */
    function updateTradeMaxClosingSlippageP(
        ITradingStorage.Id memory _tradeId,
        uint16 _maxSlippageP
    ) external;

    /**
     * @dev Updates an open trade collateral
     * @param _tradeId id of updated trade
     * @param _collateralAmount new collateral amount value (collateral precision)
     */
    function updateTradeCollateralAmount(Id memory _tradeId, uint120 _collateralAmount) external;

    /**
     * @dev Updates an open trade collateral
     * @param _tradeId id of updated trade
     * @param _collateralAmount new collateral amount value (collateral precision)
     * @param _leverage new leverage value
     * @param _openPrice new open price value
     * @param _isPartialIncrease refreshes trade liquidation params if true
     */
    function updateTradePosition(
        Id memory _tradeId,
        uint120 _collateralAmount,
        uint24 _leverage,
        uint64 _openPrice,
        bool _isPartialIncrease
    ) external;

    /**
     * @dev Updates an open order details (limit/stop)
     * @param _tradeId id of updated trade
     * @param _openPrice new open price (1e10)
     * @param _tp new take profit price (1e10)
     * @param _sl new stop loss price (1e10)
     * @param _maxSlippageP new max slippage % value (1e3)
     */
    function updateOpenOrderDetails(
        Id memory _tradeId,
        uint64 _openPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) external;

    /**
     * @dev Updates the take profit of an open trade
     * @param _tradeId the trade id
     * @param _newTp the new take profit (1e10 precision)
     */
    function updateTradeTp(Id memory _tradeId, uint64 _newTp) external;

    /**
     * @dev Updates the stop loss of an open trade
     * @param _tradeId the trade id
     * @param _newSl the new sl (1e10 precision)
     */
    function updateTradeSl(Id memory _tradeId, uint64 _newSl) external;

    /**
     * @dev Marks an open trade/limit/stop as closed
     * @param _tradeId the trade id
     */
    function closeTrade(Id memory _tradeId) external;

    /**
     * @dev Returns collateral data by index
     * @param _index the index of the supported collateral
     */
    function getCollateral(uint8 _index) external view returns (Collateral memory);

    /**
     * @dev Returns whether can open new trades with a collateral
     * @param _index the index of the collateral to check
     */
    function isCollateralActive(uint8 _index) external view returns (bool);

    /**
     * @dev Returns whether a collateral has been listed
     * @param _index the index of the collateral to check
     */
    function isCollateralListed(uint8 _index) external view returns (bool);

    /**
     * @dev Returns the number of supported collaterals
     */
    function getCollateralsCount() external view returns (uint8);

    /**
     * @dev Returns the supported collaterals
     */
    function getCollaterals() external view returns (Collateral[] memory);

    /**
     * @dev Returns the index of a supported collateral
     * @param _collateral the address of the collateral
     */
    function getCollateralIndex(address _collateral) external view returns (uint8);

    /**
     * @dev Returns the trading activated state
     */
    function getTradingActivated() external view returns (TradingActivated);

    /**
     * @dev Returns whether a trader is stored in the traders array
     * @param _trader trader to check
     */
    function getTraderStored(address _trader) external view returns (bool);

    /**
     * @dev Returns all traders that have open trades using a pagination system
     * @param _offset start index in the traders array
     * @param _limit end index in the traders array
     */
    function getTraders(uint32 _offset, uint32 _limit) external view returns (address[] memory);

    /**
     * @dev Returns open trade/limit/stop order
     * @param _trader address of the trader
     * @param _index index of the trade for trader
     */
    function getTrade(address _trader, uint32 _index) external view returns (Trade memory);

    /**
     * @dev Returns all open trades/limit/stop orders for a trader
     * @param _trader address of the trader
     */
    function getTrades(address _trader) external view returns (Trade[] memory);

    /**
     * @dev Returns all trade/limit/stop orders using a pagination system
     * @param _offset index of first trade to return
     * @param _limit index of last trade to return
     */
    function getAllTrades(uint256 _offset, uint256 _limit) external view returns (Trade[] memory);

    /**
     * @dev Returns trade info of an open trade/limit/stop order
     * @param _trader address of the trader
     * @param _index index of the trade for trader
     */
    function getTradeInfo(address _trader, uint32 _index) external view returns (TradeInfo memory);

    /**
     * @dev Returns all trade infos of open trade/limit/stop orders for a trader
     * @param _trader address of the trader
     */
    function getTradeInfos(address _trader) external view returns (TradeInfo[] memory);

    /**
     * @dev Returns all trade infos of open trade/limit/stop orders using a pagination system
     * @param _offset index of first tradeInfo to return
     * @param _limit index of last tradeInfo to return
     */
    function getAllTradeInfos(
        uint256 _offset,
        uint256 _limit
    ) external view returns (TradeInfo[] memory);

    /**


    /**
     * @dev Returns the counters of a trader (currentIndex / open count for trades/tradeInfos and pendingOrders mappings)
     * @param _trader address of the trader
     */
    function getCounters(address _trader) external view returns (Counter memory);

    /**
     * @dev Returns the liquidation params for a trade
     * @param _trader address of the trader
     * @param _index index of the trade for trader
     */
    function getTradeLiquidationParams(
        address _trader,
        uint32 _index
    ) external view returns (IPairsStorage.GroupLiquidationParams memory);

    /**
     * @dev Returns all trade liquidation params of open trade/limit/stop orders for a trader
     * @param _trader address of the trader
     */
    function getTradesLiquidationParams(
        address _trader
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory);

    /**
     * @dev Returns all trade liquidation params of open trade/limit/stop orders using a pagination system
     * @param _offset index of first liq param to return
     * @param _limit index of last liq param to return
     */
    function getAllTradesLiquidationParams(
        uint256 _offset,
        uint256 _limit
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory);

    /**
     * @dev Returns the address of the liquidityProvider
     */
    function getBorrowingProvider() external view returns (address);

    /**
     * @dev Emitted when the trading activated state is updated
     * @param activated the new trading activated state
     */
    event TradingActivatedUpdated(TradingActivated activated);

    /**
     * @dev Emitted when a new supported collateral is added
     * @param collateral the address of the collateral
     * @param index the index of the supported collateral
     */
    event CollateralAdded(address collateral, uint8 index);

    /**
     * @dev Emitted when an existing supported collateral active state is updated
     * @param index the index of the supported collateral
     * @param isActive the new active state
     */
    event CollateralUpdated(uint8 indexed index, bool isActive);

    /**
     * @dev Emitted when an existing borrowing provider is updated
     * @param borrowingProvider borrowing provider address
     */
    event BorrowingProviderUpdated(address indexed borrowingProvider);

    /**
     * @dev Emitted when an existing supported collateral is disabled (can still close trades but not open new ones)
     * @param index the index of the supported collateral
     */
    event CollateralDisabled(uint8 index);

    /**
     * @dev Emitted when a new trade is stored
     * @param trade the trade stored
     * @param tradeInfo the trade info stored
     * @param liquidationParams the trade liquidation params stored
     */
    event TradeStored(
        Trade trade,
        TradeInfo tradeInfo,
        IPairsStorage.GroupLiquidationParams liquidationParams
    );

    /**
     * @dev Emitted when the max closing slippage % of an open trade is updated
     * @param tradeId id of the updated trade
     * @param maxClosingSlippageP new max closing slippage % value (1e3 precision)
     */
    event TradeMaxClosingSlippagePUpdated(Id tradeId, uint16 maxClosingSlippageP);

    /**
     * @dev Emitted when an open trade collateral is updated
     * @param tradeId id of the updated trade
     * @param collateralAmount new collateral value (collateral precision)
     */
    event TradeCollateralUpdated(Id tradeId, uint120 collateralAmount);

    /**
     * @dev Emitted when an open trade collateral is updated
     * @param tradeId id of the updated trade
     * @param collateralAmount new collateral value (collateral precision)
     * @param leverage new leverage value if present
     * @param openPrice new open price value if present
     * @param isPartialIncrease true if trade liquidation params were refreshed
     */
    event TradePositionUpdated(
        Id tradeId,
        uint120 collateralAmount,
        uint24 leverage,
        uint64 openPrice,
        uint64 newTp,
        uint64 newSl,
        bool isPartialIncrease
    );

    /**
     * @dev Emitted when an existing trade/limit order/stop order is updated
     * @param tradeId id of the updated trade
     * @param openPrice new open price value (1e10)
     * @param tp new take profit value (1e10)
     * @param sl new stop loss value (1e10)
     * @param maxSlippageP new max slippage % value (1e3)
     */
    event OpenOrderDetailsUpdated(
        Id tradeId,
        uint64 openPrice,
        uint64 tp,
        uint64 sl,
        uint16 maxSlippageP
    );

    /**
     * @dev Emitted when the take profit of an open trade is updated
     * @param tradeId the trade id
     * @param newTp the new take profit (1e10 precision)
     */
    event TradeTpUpdated(Id tradeId, uint64 newTp);

    /**
     * @dev Emitted when the stop loss of an open trade is updated
     * @param tradeId the trade id
     * @param newSl the new sl (1e10 precision)
     */
    event TradeSlUpdated(Id tradeId, uint64 newSl);

    /**
     * @dev Emitted when an open trade is closed
     * @param tradeId the trade id
     */
    event TradeClosed(Id tradeId);

    error MissingCollaterals();
    error CollateralAlreadyActive();
    error CollateralAlreadyDisabled();
    error TradePositionSizeZero();
    error TradeOpenPriceZero();
    error TradePairNotListed();
    error TradeTpInvalid();
    error TradeSlInvalid();
    error MaxSlippageZero();
    error TradeInfoCollateralPriceUsdZero();
}
