// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
//import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
//import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/trade/IJavMultiCollatDiamond.sol";
import "../../interfaces/trade/IChainlinkFeed.sol";

import "./AddressStoreUtils.sol";
import "./StorageUtils.sol";
import "./ChainlinkClientUtils.sol";
import "./PackingUtils.sol";

/**
 * @custom:version 8
 * @dev GNSPriceAggregator facet internal library
 */
library PriceAggregatorUtils {
    using PackingUtils for uint256;
    using SafeERC20 for IERC20;
    using Chainlink for Chainlink.Request;

    uint256 private constant PRECISION = 1e10;
    uint256 private constant MAX_ORACLE_NODES = 20;
    uint256 private constant MIN_ANSWERS = 3;
    uint32 private constant MIN_TWAP_PERIOD = 1 hours / 2;
    uint32 private constant MAX_TWAP_PERIOD = 4 hours;

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function initializePriceAggregator(
        address _linkErc677,
        IChainlinkFeed _linkUsdPriceFeed,
        uint24 _twapInterval,
        uint8 _minAnswers,
        address[] memory _oracles,
        bytes32[2] memory _jobIds,
        uint8[] calldata _collateralIndices,
        IUniswapV3Pool[] memory _gnsCollateralUniV3Pools,
        IChainlinkFeed[] memory _collateralUsdPriceFeeds
    ) internal {
        if (
            _collateralIndices.length != _gnsCollateralUniV3Pools.length ||
            _collateralIndices.length != _collateralUsdPriceFeeds.length
        ) revert IGeneralErrors.WrongLength();

        //        ChainlinkClientUtils.setChainlinkToken(_linkErc677);
        updateLinkUsdPriceFeed(_linkUsdPriceFeed);
        updateTwapInterval(_twapInterval);
        updateMinAnswers(_minAnswers);

        for (uint256 i = 0; i < _oracles.length; ++i) {
            addOracle(_oracles[i]);
        }

        setMarketJobId(_jobIds[0]);
        setLimitJobId(_jobIds[1]);

        for (uint8 i = 0; i < _collateralIndices.length; ++i) {
            updateCollateralGnsUniV3Pool(_collateralIndices[i], _gnsCollateralUniV3Pools[i]);
            updateCollateralUsdPriceFeed(_collateralIndices[i], _collateralUsdPriceFeeds[i]);
        }
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updateLinkUsdPriceFeed(IChainlinkFeed _value) internal {
        if (address(_value) == address(0)) revert IGeneralErrors.ZeroValue();

        _getStorage().linkUsdPriceFeed = _value;

        emit IPriceAggregatorUtils.LinkUsdPriceFeedUpdated(address(_value));
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updateCollateralUsdPriceFeed(
        uint8 _collateralIndex,
        IChainlinkFeed _value
    ) internal validCollateralIndex(_collateralIndex) {
        if (address(_value) == address(0)) revert IGeneralErrors.ZeroValue();
        if (_value.decimals() != 8) revert IPriceAggregatorUtils.WrongCollateralUsdDecimals();

        _getStorage().collateralUsdPriceFeed[_collateralIndex] = _value;

        emit IPriceAggregatorUtils.CollateralUsdPriceFeedUpdated(_collateralIndex, address(_value));
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updateCollateralGnsUniV3Pool(
        uint8 _collateralIndex,
        IUniswapV3Pool _uniV3Pool
    ) internal validCollateralIndex(_collateralIndex) {
        if (address(_uniV3Pool) == address(0)) revert IGeneralErrors.ZeroValue();

        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();
        IPriceAggregator.UniV3PoolInfo storage poolInfo = s.collateralGnsUniV3Pools[
            _collateralIndex
        ];

        poolInfo.pool = _uniV3Pool;
        poolInfo.isGnsToken0InLp = _uniV3Pool.token0() == AddressStoreUtils.getAddresses().gns;

        emit IPriceAggregatorUtils.CollateralGnsUniV3PoolUpdated(_collateralIndex, poolInfo);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updateTwapInterval(uint24 _twapInterval) internal {
        if (_twapInterval < MIN_TWAP_PERIOD || _twapInterval > MAX_TWAP_PERIOD)
            revert IGeneralErrors.WrongParams();

        _getStorage().twapInterval = _twapInterval;

        emit IPriceAggregatorUtils.TwapIntervalUpdated(_twapInterval);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function updateMinAnswers(uint8 _value) internal {
        if (_value < MIN_ANSWERS) revert IGeneralErrors.BelowMin();
        if (_value % 2 == 0) revert IGeneralErrors.WrongParams();

        _getStorage().minAnswers = _value;

        emit IPriceAggregatorUtils.MinAnswersUpdated(_value);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function addOracle(address _a) internal {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();

        if (_a == address(0)) revert IGeneralErrors.ZeroValue();
        if (s.oracles.length >= MAX_ORACLE_NODES) revert IGeneralErrors.AboveMax();

        for (uint256 i; i < s.oracles.length; ++i) {
            if (s.oracles[i] == _a) revert IPriceAggregatorUtils.OracleAlreadyListed();
        }

        s.oracles.push(_a);

        emit IPriceAggregatorUtils.OracleAdded(s.oracles.length - 1, _a);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function replaceOracle(uint256 _index, address _a) internal {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();

        if (_index >= s.oracles.length) revert IGeneralErrors.WrongIndex();
        if (_a == address(0)) revert IGeneralErrors.ZeroValue();

        address oldNode = s.oracles[_index];
        s.oracles[_index] = _a;

        emit IPriceAggregatorUtils.OracleReplaced(_index, oldNode, _a);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function removeOracle(uint256 _index) internal {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();

        if (_index >= s.oracles.length) revert IGeneralErrors.WrongIndex();

        address oldNode = s.oracles[_index];

        s.oracles[_index] = s.oracles[s.oracles.length - 1];
        s.oracles.pop();

        emit IPriceAggregatorUtils.OracleRemoved(_index, oldNode);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function setMarketJobId(bytes32 _jobId) internal {
        if (_jobId == bytes32(0)) revert IGeneralErrors.ZeroValue();

        _getStorage().jobIds[0] = _jobId;

        emit IPriceAggregatorUtils.JobIdUpdated(0, _jobId);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function setLimitJobId(bytes32 _jobId) internal {
        if (_jobId == bytes32(0)) revert IGeneralErrors.ZeroValue();

        _getStorage().jobIds[1] = _jobId;

        emit IPriceAggregatorUtils.JobIdUpdated(1, _jobId);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getPrice(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        ITradingStorage.Id memory _orderId,
        ITradingStorage.PendingOrderType _orderType,
        uint256 _positionSizeCollateral,
        uint256 _fromBlock
    ) internal validCollateralIndex(_collateralIndex) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();

        bool isLookback = _orderType != ITradingStorage.PendingOrderType.MARKET_OPEN &&
            _orderType != ITradingStorage.PendingOrderType.MARKET_CLOSE;

        bytes32 job = isLookback ? s.jobIds[1] : s.jobIds[0];

        Chainlink.Request memory linkRequest = ChainlinkClientUtils.buildChainlinkRequest(
            job,
            address(this),
            IPriceAggregatorUtils.fulfill.selector
        );

        //        {
        //            (string memory from, string memory to) = _getMultiCollatDiamond().pairJob(_pairIndex);
        //
        //            linkRequest.add("from", from);
        //            linkRequest.add("to", to);
        //
        //            if (isLookback) {
        //                linkRequest.addUint("fromBlock", _fromBlock);
        //            }
        //
        //            emit IPriceAggregatorUtils.LinkRequestCreated(linkRequest);
        //        }

        uint256 linkFeePerNode = getLinkFee(_collateralIndex, _pairIndex, _positionSizeCollateral) /
            s.oracles.length;
        {
            IPriceAggregator.Order memory order = IPriceAggregator.Order({
                user: _orderId.user,
                index: _orderId.index,
                orderType: _orderType,
                pairIndex: uint16(_pairIndex),
                isLookback: isLookback,
                __placeholder: 0
            });

            for (uint256 i; i < s.oracles.length; ++i) {
                bytes32 requestId = ChainlinkClientUtils.sendChainlinkRequestTo(
                    s.oracles[i],
                    linkRequest,
                    linkFeePerNode
                );
                s.orders[requestId] = order;
            }
        }

        emit IPriceAggregatorUtils.PriceRequested(
            _collateralIndex,
            _orderId,
            _orderType,
            _pairIndex,
            job,
            s.oracles.length,
            linkFeePerNode,
            _fromBlock,
            isLookback
        );
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function fulfill(bytes32 _requestId, uint256 _priceData) internal {
        ChainlinkClientUtils.validateChainlinkCallback(_requestId);

        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();

        IPriceAggregator.Order memory order = s.orders[_requestId];
        ITradingStorage.Id memory orderId = ITradingStorage.Id({
            user: order.user,
            index: order.index
        });

        IPriceAggregator.OrderAnswer[] storage orderAnswers = s.orderAnswers[orderId.user][
            orderId.index
        ];
        uint8 minAnswers = s.minAnswers;
        bool usedInMedian = orderAnswers.length < minAnswers;

        if (usedInMedian) {
            IPriceAggregator.OrderAnswer memory newAnswer;
            (newAnswer.open, newAnswer.high, newAnswer.low, newAnswer.ts) = _priceData
                .unpack256To64();

            if (
                order.isLookback &&
                ((newAnswer.high > 0 || newAnswer.low > 0) &&
                    (newAnswer.high < newAnswer.open ||
                        newAnswer.low > newAnswer.open ||
                        newAnswer.low == 0))
            ) revert IPriceAggregatorUtils.InvalidCandle();

            orderAnswers.push(newAnswer);

            if (orderAnswers.length == minAnswers) {
                ITradingCallbacks.AggregatorAnswer memory finalAnswer;

                finalAnswer.orderId = orderId;
                finalAnswer.spreadP = _getMultiCollatDiamond().pairSpreadP(order.pairIndex);

                if (order.isLookback) {
                    (finalAnswer.open, finalAnswer.high, finalAnswer.low) = _medianLookbacks(
                        orderAnswers
                    );
                } else {
                    finalAnswer.price = _median(orderAnswers);
                }

                if (order.orderType == ITradingStorage.PendingOrderType.MARKET_OPEN) {
                    _getMultiCollatDiamond().openTradeMarketCallback(finalAnswer);
                } else if (order.orderType == ITradingStorage.PendingOrderType.MARKET_CLOSE) {
                    _getMultiCollatDiamond().closeTradeMarketCallback(finalAnswer);
                } else if (
                    order.orderType == ITradingStorage.PendingOrderType.LIMIT_OPEN ||
                    order.orderType == ITradingStorage.PendingOrderType.STOP_OPEN
                ) {
                    _getMultiCollatDiamond().executeTriggerOpenOrderCallback(finalAnswer);
                } else {
                    _getMultiCollatDiamond().executeTriggerCloseOrderCallback(finalAnswer);
                }

                emit IPriceAggregatorUtils.TradingCallbackExecuted(finalAnswer, order.orderType);
            }
        }

        emit IPriceAggregatorUtils.PriceReceived(
            orderId,
            order.pairIndex,
            _requestId,
            _priceData,
            order.isLookback,
            usedInMedian
        );
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function claimBackLink() internal {
        IERC20 link = IERC20(getChainlinkToken());
        uint256 linkAmount = link.balanceOf(address(this));

        link.safeTransfer(msg.sender, linkAmount);

        emit IPriceAggregatorUtils.LinkClaimedBack(linkAmount);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getLinkFee(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        uint256 _positionSizeCollateral // collateral precision
    ) internal view returns (uint256) {
        (, int256 linkPriceUsd, , , ) = _getStorage().linkUsdPriceFeed.latestRoundData();

        // NOTE: all [token / USD] feeds are 8 decimals
        return
            (getUsdNormalizedValue(
                _collateralIndex,
                _getMultiCollatDiamond().pairOracleFeeP(_pairIndex) * _positionSizeCollateral
            ) * 1e8) /
            uint256(linkPriceUsd) /
            PRECISION /
            100;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralPriceUsd(uint8 _collateralIndex) internal view returns (uint256) {
        (, int256 collateralPriceUsd, , , ) = _getStorage()
            .collateralUsdPriceFeed[_collateralIndex]
            .latestRoundData();

        return uint256(collateralPriceUsd);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _collateralValue
    ) internal view returns (uint256) {
        return
            (_collateralValue *
                _getCollateralPrecisionDelta(_collateralIndex) *
                getCollateralPriceUsd(_collateralIndex)) / 1e8;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralFromUsdNormalizedValue(
        uint8 _collateralIndex,
        uint256 _normalizedValue
    ) internal view returns (uint256) {
        return
            (_normalizedValue * 1e8) /
            getCollateralPriceUsd(_collateralIndex) /
            _getCollateralPrecisionDelta(_collateralIndex);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getGnsPriceUsd(uint8 _collateralIndex) internal view returns (uint256) {
        return getGnsPriceUsd(_collateralIndex, getGnsPriceCollateralIndex(_collateralIndex));
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getGnsPriceUsd(
        uint8 _collateralIndex,
        uint256 _gnsPriceCollateral
    ) internal view returns (uint256) {
        return (_gnsPriceCollateral * getCollateralPriceUsd(_collateralIndex)) / 1e8;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getGnsPriceCollateralAddress(
        address _collateral
    ) internal view returns (uint256 _price) {
        return getGnsPriceCollateralIndex(_getMultiCollatDiamond().getCollateralIndex(_collateral));
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getGnsPriceCollateralIndex(
        uint8 _collateralIndex
    ) internal view returns (uint256 _price) {
        IPriceAggregator.PriceAggregatorStorage storage s = _getStorage();

        uint32[] memory secondsAgos = new uint32[](2);
        uint32 twapInterval = uint32(s.twapInterval);

        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;

        IPriceAggregator.UniV3PoolInfo memory poolInfo = s.collateralGnsUniV3Pools[
            _collateralIndex
        ];
        (int56[] memory tickCumulatives, ) = poolInfo.pool.observe(secondsAgos);

        return
            _tickCumulativesToTokenPrice(
                tickCumulatives,
                twapInterval,
                _getCollateralPrecisionDelta(_collateralIndex),
                poolInfo.isGnsToken0InLp
            );
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getLinkUsdPriceFeed() internal view returns (IChainlinkFeed) {
        return _getStorage().linkUsdPriceFeed;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getTwapInterval() internal view returns (uint24) {
        return _getStorage().twapInterval;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getMinAnswers() internal view returns (uint8) {
        return _getStorage().minAnswers;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getMarketJobId() internal view returns (bytes32) {
        return _getStorage().jobIds[0];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getLimitJobId() internal view returns (bytes32) {
        return _getStorage().jobIds[1];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getOracle(uint256 _index) internal view returns (address) {
        return _getStorage().oracles[_index];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getOracles() internal view returns (address[] memory) {
        return _getStorage().oracles;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralGnsUniV3Pool(
        uint8 _collateralIndex
    ) internal view returns (IPriceAggregator.UniV3PoolInfo memory) {
        return _getStorage().collateralGnsUniV3Pools[_collateralIndex];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getCollateralUsdPriceFeed(
        uint8 _collateralIndex
    ) internal view returns (IChainlinkFeed) {
        return _getStorage().collateralUsdPriceFeed[_collateralIndex];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getPriceAggregatorOrder(
        bytes32 _requestId
    ) internal view returns (IPriceAggregator.Order memory) {
        return _getStorage().orders[_requestId];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getPriceAggregatorOrderAnswers(
        ITradingStorage.Id calldata _orderId
    ) internal view returns (IPriceAggregator.OrderAnswer[] memory) {
        return _getStorage().orderAnswers[_orderId.user][_orderId.index];
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getChainlinkToken() internal view returns (address) {
        return address(_getStorage().linkErc677);
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getRequestCount() internal view returns (uint256) {
        return _getStorage().requestCount;
    }

    /**
     * @dev Check IPriceAggregatorUtils interface for documentation
     */
    function getPendingRequest(bytes32 _id) internal view returns (address) {
        return _getStorage().pendingRequests[_id];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_PRICE_AGGREGATOR_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (IPriceAggregator.PriceAggregatorStorage storage s)
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
     * @dev Reverts if collateral index is not valid
     */
    modifier validCollateralIndex(uint8 _collateralIndex) {
        if (!_getMultiCollatDiamond().isCollateralListed(_collateralIndex)) {
            revert IGeneralErrors.InvalidCollateralIndex();
        }
        _;
    }

    /**
     * @dev returns median price of array (1 price only)
     * @param _array array of values
     */
    function _median(IPriceAggregator.OrderAnswer[] memory _array) internal pure returns (uint64) {
        uint256 length = _array.length;

        uint256[] memory prices = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            prices[i] = _array[i].open;
        }

        _sort(prices, 0, length);

        return
            uint64(
                length % 2 == 0
                    ? (prices[length / 2 - 1] + prices[length / 2]) / 2
                    : prices[length / 2]
            );
    }

    /**
     * @dev returns median prices of array (open, high, low)
     * @param _array array of values
     */
    function _medianLookbacks(
        IPriceAggregator.OrderAnswer[] memory _array
    ) internal pure returns (uint64 open, uint64 high, uint64 low) {
        uint256 length = _array.length;

        uint256[] memory opens = new uint256[](length);
        uint256[] memory highs = new uint256[](length);
        uint256[] memory lows = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            opens[i] = _array[i].open;
            highs[i] = _array[i].high;
            lows[i] = _array[i].low;
        }

        _sort(opens, 0, length);
        _sort(highs, 0, length);
        _sort(lows, 0, length);

        bool isLengthEven = length % 2 == 0;
        uint256 halfLength = length / 2;

        open = uint64(
            isLengthEven ? (opens[halfLength - 1] + opens[halfLength]) / 2 : opens[halfLength]
        );
        high = uint64(
            isLengthEven ? (highs[halfLength - 1] + highs[halfLength]) / 2 : highs[halfLength]
        );
        low = uint64(
            isLengthEven ? (lows[halfLength - 1] + lows[halfLength]) / 2 : lows[halfLength]
        );
    }

    /**
     * @dev Returns TWAP price (1e10 precision) from tickCumulatives data
     * @param _tickCumulatives array of tickCumulatives
     * @param _twapInterval TWAP interval
     * @param _precisionDelta precision delta of collateral
     * @param _isGnsToken0InLp true if GNS is token0 in LP
     *
     * Inspired from https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol
     */
    function _tickCumulativesToTokenPrice(
        int56[] memory _tickCumulatives,
        uint32 _twapInterval,
        uint256 _precisionDelta,
        bool _isGnsToken0InLp
    ) internal pure returns (uint256) {
        //        if (_tickCumulatives.length != 2) revert IGeneralErrors.WrongLength();
        //
        //        int56 tickCumulativesDelta = _tickCumulatives[1] - _tickCumulatives[0];
        //        int56 twapIntervalInt = int56(int32(_twapInterval));
        //
        //        int24 arithmeticMeanTick = int24(tickCumulativesDelta / twapIntervalInt);
        //        // Always round to negative infinity
        //        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % twapIntervalInt != 0)) arithmeticMeanTick--;
        //
        //        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick); // sqrt(token1/token0*2^96)
        //        uint256 priceX96 = (FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96) * PRECISION); // token1/token0*2^96*1e10
        //
        //        return
        //            _isGnsToken0InLp
        //                ? (priceX96 * _precisionDelta) / 2 ** 96 // 1e6/1e18*2^96*1e10 * 1e12 / 2^96 = 1e18/1e18*1e10
        //                : (PRECISION ** 2) / (priceX96 / _precisionDelta / 2 ** 96); // 1e10^2 / (1e18/1e6*2^96*1e10 / 1e12 / 2^96) = 1e10^2 / (1e18/1e18*1e10) = 1e18/1e18*1e10
        return 5;
    }

    /**
     * @dev swaps two elements in array
     * @param _array array of values
     * @param _i index of first element
     * @param _j index of second element
     */
    function _swap(uint256[] memory _array, uint256 _i, uint256 _j) internal pure {
        (_array[_i], _array[_j]) = (_array[_j], _array[_i]);
    }

    /**
     * @dev sorts array of uint256 values
     * @param _array array of values
     * @param begin start index
     * @param end end index
     */
    function _sort(uint256[] memory _array, uint256 begin, uint256 end) internal pure {
        if (begin >= end) {
            return;
        }

        uint256 j = begin;
        uint256 pivot = _array[j];

        for (uint256 i = begin + 1; i < end; ++i) {
            if (_array[i] < pivot) {
                _swap(_array, i, ++j);
            }
        }

        _swap(_array, begin, j);
        _sort(_array, begin, j);
        _sort(_array, j + 1, end);
    }

    /**
     * @dev Returns precision delta of collateral as uint256
     * @param _collateralIndex index of collateral
     */
    function _getCollateralPrecisionDelta(uint8 _collateralIndex) internal view returns (uint256) {
        return uint256(_getMultiCollatDiamond().getCollateral(_collateralIndex).precisionDelta);
    }
}
