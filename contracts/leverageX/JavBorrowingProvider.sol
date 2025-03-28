// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../libraries/leverageX/PriceAggregatorUtils.sol";
import "../libraries/leverageX/CollateralUtils.sol";
import "../abstract/TearmsAndCondUtils.sol";
import "../base/BaseUpgradable.sol";

import "../interfaces/leverageX/IJavBorrowingProvider.sol";
import "../interfaces/IJavPriceAggregator.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/helpers/IJavBurner.sol";
import "../interfaces/helpers/IJavInfoAggregator.sol";

contract JavBorrowingProvider is
    IJavBorrowingProvider,
    IGeneralErrors,
    TermsAndCondUtils,
    ReentrancyGuardUpgradeable,
    BaseUpgradable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    struct TokenInfo {
        address asset;
        bytes32 priceFeed;
        uint256 targetWeightage;
        bool isActive;
    }

    struct RebalanceInfo {
        uint8 tokenId;
        uint256 targetValue;
        uint256 currentValue;
        uint256 excessValue;
        bool isSell;
    }

    struct SwapTokenInfo {
        address tokenIn;
        address tokenOut;
        uint256 amount;
    }

    struct TokenPrecisionInfo {
        uint128 precision;
        uint128 precisionDelta;
    }

    // Parameters (constant)
    uint256 constant PRECISION_18 = 1e18;

    IJavPriceAggregator public priceAggregator;
    IRouter public swapRouter;
    address public pnlHandler;
    address public llpToken;
    uint256 public buyFee; // @custom:deprecated
    uint256 public sellFee; // @custom:deprecated

    TokenInfo[] public tokens;
    mapping(address => TokenPrecisionInfo) public tokensPrecision;

    // Price state
    uint256 public rewardsAmountUsd; // PRECISION_18
    mapping(uint256 => int256) public accPnlPerToken; // PRECISION_18 (updated in real-time)
    mapping(uint256 => uint256) public accRewardsPerToken; // PRECISION_18

    // Parameters (adjustable)
    uint256 public lossesBurnP; // PRECISION_18 (% of all losses)
    mapping(uint256 => uint256) public tokenAmount; // PRECISION_18
    EnumerableSet.AddressSet private _whiteListAddresses; // @custom:deprecated
    bool public isBuyActive;
    bool public isSellActive;
    address public termsAndConditionsAddress;
    address public javBurner;
    address public javInfoAggregator;
    uint256 public minBuyAmountUsd; //1e18
    uint32[] public baseFees; //1e4
    uint32[] public usdThresholds; // clear
    uint32[] public javThresholds; // clear
    uint32[] public reductionFactors; //1e4
    uint32[] public sellFees; //1e4

    /* ========== EVENTS ========== */
    event AddToken(TokenInfo tokenInfo);
    event BuyLLP(
        address indexed user,
        address tokenIn,
        uint256 tokenInID,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeAmount,
        uint256 feeAmountUsd
    );
    event SellLLP(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 tokenOutID,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeAmount,
        uint256 feeAmountUsd
    );
    event UpdateToken(
        uint256 indexed tokenId,
        address asset,
        bytes32 priceFeed,
        uint256 targetWeightage,
        bool isActive
    );
    event AddLiquidity(uint256 indexed tokenId, uint256 amount);

    modifier validToken(uint256 _tokenId) {
        require(_tokenId < tokens.length, "JavBorrowingProvider: Invalid token");
        require(tokens[_tokenId].isActive, "JavBorrowingProvider: Token is inactive");
        _;
    }

    modifier onlyActiveBuy() {
        require(isBuyActive, InactiveBuy());
        _;
    }

    modifier onlyActiveSell() {
        require(isSellActive, InactiveSell());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _priceAggregator,
        address _swapRouter,
        address _llpToken,
        address _pnlHandler,
        TokenInfo[] memory _tokens
    ) external initializer {
        priceAggregator = IJavPriceAggregator(_priceAggregator);
        swapRouter = IRouter(_swapRouter);
        pnlHandler = _pnlHandler;
        llpToken = _llpToken;

        CollateralUtils.CollateralConfig memory collateralConfig = CollateralUtils
            .getCollateralConfig(_llpToken);
        tokensPrecision[_llpToken] = TokenPrecisionInfo({
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });

        __Base_init();
        __ReentrancyGuard_init();

        for (uint8 i = 0; i < _tokens.length; ++i) {
            addToken(_tokens[i]);
        }
    }

    function addToken(TokenInfo memory tokenInfo) public onlyAdmin {
        CollateralUtils.CollateralConfig memory collateralConfig = CollateralUtils
            .getCollateralConfig(tokenInfo.asset);
        tokensPrecision[tokenInfo.asset] = TokenPrecisionInfo({
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });
        tokens.push(tokenInfo);

        emit AddToken(tokenInfo);
    }

    function updateToken(
        uint256 _tokenId,
        TokenInfo memory _tokenInfo
    ) external onlyAdmin validToken(_tokenId) {
        TokenInfo storage _token = tokens[_tokenId];
        CollateralUtils.CollateralConfig memory collateralConfig = CollateralUtils
            .getCollateralConfig(_tokenInfo.asset);

        _token.asset = _tokenInfo.asset;
        _token.priceFeed = _tokenInfo.priceFeed;
        _token.targetWeightage = _tokenInfo.targetWeightage;
        _token.isActive = _tokenInfo.isActive;

        tokensPrecision[_tokenInfo.asset] = TokenPrecisionInfo({
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });

        emit UpdateToken(
            _tokenId,
            _tokenInfo.asset,
            _tokenInfo.priceFeed,
            _tokenInfo.targetWeightage,
            _tokenInfo.isActive
        );
    }

    function toggleBuyActiveState() external onlyAdmin {
        bool toggled = !isBuyActive;
        isBuyActive = toggled;

        emit BuyActiveStateUpdated(toggled);
    }

    function toggleSellActiveState() external onlyAdmin {
        bool toggled = !isSellActive;
        isSellActive = toggled;

        emit SellActiveStateUpdated(toggled);
    }

    function setTermsAndConditionsAddress(
        address _termsAndConditionsAddress
    ) external onlyAdmin nonZeroAddress(_termsAndConditionsAddress) {
        termsAndConditionsAddress = _termsAndConditionsAddress;

        emit SetTermsAndConditionsAddress(_termsAndConditionsAddress);
    }

    function setJavBurner(address _javBurner) external onlyAdmin nonZeroAddress(_javBurner) {
        javBurner = _javBurner;

        emit SetJavBurner(_javBurner);
    }

    function setJavInfoAggregator(
        address _javInfoAggregator
    ) external onlyAdmin nonZeroAddress(_javInfoAggregator) {
        javInfoAggregator = _javInfoAggregator;

        emit SetJavInfoAggregator(_javInfoAggregator);
    }

    function setMinBuyAmountUsd(uint256 _minBuyAmountUsd) external onlyAdmin {
        minBuyAmountUsd = _minBuyAmountUsd;

        emit SetMinBuyAmountUsd(_minBuyAmountUsd);
    }

    function setBuyConfiguration(
        uint32[] memory _baseFees,
        uint32[] memory _usdThresholds
    ) external onlyAdmin {
        require(_baseFees.length == _usdThresholds.length, InvalidInputLength());

        baseFees = _baseFees;
        usdThresholds = _usdThresholds;

        emit SetBuyConfiguration(_baseFees, _usdThresholds);
    }

    function setJavAmountConfiguration(
        uint32[] memory _javThresholds,
        uint32[] memory _reductionFactors
    ) external onlyAdmin {
        require(_javThresholds.length == _reductionFactors.length, InvalidInputLength());

        javThresholds = _javThresholds;
        reductionFactors = _reductionFactors;

        emit SetJavAmountConfiguration(_javThresholds, _reductionFactors);
    }

    function setSellFees(uint32[] memory _sellFees) external onlyAdmin {
        require(javThresholds.length == _sellFees.length, InvalidInputLength());
        sellFees = _sellFees;

        emit SetSellFees(_sellFees);
    }

    function initialBuy(
        uint256 _inputToken,
        uint256 _amount,
        uint256 _llpAmount
    ) external onlyAdmin validToken(_inputToken) {
        require(
            IERC20(llpToken).totalSupply() == 0,
            "JavBorrowingProvider: Purchase not available"
        );
        TokenInfo memory _token = tokens[_inputToken];
        tokenAmount[_inputToken] += _amount;

        IERC20(_token.asset).safeTransferFrom(_msgSender(), address(this), _amount);
        IERC20Extended(llpToken).mint(_msgSender(), _llpAmount);

        emit BuyLLP(_msgSender(), _token.asset, _inputToken, llpToken, _amount, _llpAmount, 0, 0);
    }

    /**
     * @notice Function to buy LLP token
     * @param _inputToken: input token id for buy
     * @param _amount: amount
     */
    function buyLLP(
        uint256 _inputToken,
        uint256 _amount
    )
        external
        nonReentrant
        onlyActiveBuy
        whenNotPaused
        validToken(_inputToken)
        onlyAgreeToTerms(termsAndConditionsAddress)
    {
        require(IERC20(llpToken).totalSupply() > 0, "JavBorrowingProvider: Purchase not available");
        TokenInfo memory _token = tokens[_inputToken];
        require(
            IERC20(_token.asset).balanceOf(_msgSender()) >= _amount,
            "JavBorrowingProvider: invalid balance for buy"
        );

        _buyLLP(_inputToken, _token, _amount);
    }

    /**
     * @notice Function to sell LLP token
     * @param _outputToken: input token id for buy
     * @param _amount: amount
     */
    function sellLLP(
        uint256 _outputToken,
        uint256 _amount
    ) external nonReentrant onlyActiveSell whenNotPaused validToken(_outputToken) {
        require(IERC20(llpToken).totalSupply() > 0, "JavBorrowingProvider: Sell not available");
        TokenInfo memory _token = tokens[_outputToken];
        require(
            IERC20(llpToken).balanceOf(_msgSender()) >= _amount,
            "JavBorrowingProvider: invalid balance for sell"
        );

        _sellLLP(_outputToken, _token, _amount);
    }

    function rebalanceTokens() external {
        //        _rebalance();
    }

    function updatePnlHandler(address newValue) external onlyOwner {
        if (newValue == address(0)) revert AddressZero();
        pnlHandler = newValue;
        emit PnlHandlerUpdated(newValue);
    }

    // Distributes a reward
    function distributeReward(
        uint8 _collateralIndex,
        uint256 assets
    ) external validToken(_collateralIndex) {
        TokenInfo memory _token = tokens[_collateralIndex];
        address sender = _msgSender();
        IERC20(_token.asset).safeTransferFrom(sender, address(this), assets);

        uint256 usdAmount = (assets *
            _getUsdPrice(_token.priceFeed) *
            tokensPrecision[_token.asset].precisionDelta) / PRECISION_18;
        rewardsAmountUsd += usdAmount;

        accRewardsPerToken[_collateralIndex] +=
            (assets * PRECISION_18) /
            IERC20(llpToken).totalSupply();

        emit RewardDistributed(sender, _collateralIndex, assets, usdAmount);
    }

    // PnL interactions (happens often, so also used to trigger other actions)
    function sendAssets(
        uint8 _collateralIndex,
        uint256 assets,
        address receiver
    ) external validToken(_collateralIndex) {
        TokenInfo memory _token = tokens[_collateralIndex];
        address sender = _msgSender();
        if (sender != pnlHandler) revert OnlyTradingPnlHandler();

        int256 accPnlDelta = int256((assets * PRECISION_18) / IERC20(llpToken).totalSupply());

        accPnlPerToken[_collateralIndex] += accPnlDelta;
        if (accPnlPerToken[_collateralIndex] > int256(maxAccPnlPerToken(_collateralIndex)))
            revert NotEnoughAssets();

        if (assets > tokenAmount[_collateralIndex]) {
            revert NotEnoughAssets();
        }
        tokenAmount[_collateralIndex] -= assets;
        IERC20(_token.asset).safeTransfer(receiver, assets);

        emit AssetsSent(sender, receiver, assets);
    }

    function receiveAssets(
        uint8 _collateralIndex,
        uint256 assets,
        address user
    ) external validToken(_collateralIndex) {
        TokenInfo memory _token = tokens[_collateralIndex];
        address sender = _msgSender();
        IERC20(_token.asset).safeTransferFrom(sender, address(this), assets);

        tokenAmount[_collateralIndex] += assets;

        uint256 assetsLessDeplete = assets;

        if (accPnlPerToken[_collateralIndex] < 0) {
            uint256 depleteAmount = (assets * lossesBurnP) / PRECISION_18 / 100;
            assetsLessDeplete -= depleteAmount;
        }

        int256 accPnlDelta = int256(
            (assetsLessDeplete * PRECISION_18) / IERC20(llpToken).totalSupply()
        );
        accPnlPerToken[_collateralIndex] -= accPnlDelta;

        emit AssetsReceived(sender, user, assets, assetsLessDeplete);
    }

    function addLiquidity(
        uint256 _inputToken,
        uint256 _amount
    ) external onlyAdmin validToken(_inputToken) {
        TokenInfo memory _token = tokens[_inputToken];
        require(
            IERC20(_token.asset).balanceOf(_msgSender()) >= _amount,
            "JavBorrowingProvider: invalid balance add liquidity"
        );
        IERC20(_token.asset).safeTransferFrom(_msgSender(), address(this), _amount);
        tokenAmount[_inputToken] += _amount;

        emit AddLiquidity(_inputToken, _amount);
    }

    // View helper functions
    function maxAccPnlPerToken(
        uint8 _tokenIndex
    ) public view validToken(_tokenIndex) returns (uint256) {
        // PRECISION_18
        return PRECISION_18 + accRewardsPerToken[_tokenIndex];
    }

    // Getters

    function tvl() external view returns (uint256) {
        return _calculateTotalTvlUsd();
    }

    function tokenTvl(uint256 _tokenId) external view validToken(_tokenId) returns (uint256) {
        TokenInfo memory _token = tokens[_tokenId];
        return _calculateTvlUsd(_tokenId, _token);
    }

    function llpPrice() external view returns (uint256) {
        return _llpPrice();
    }

    function tokensCount() external view returns (uint256) {
        return tokens.length;
    }

    function getWhiteListAddresses() external view returns (address[] memory) {
        return _whiteListAddresses.values();
    }

    function _buyLLP(uint256 _tokenId, TokenInfo memory _inputToken, uint256 _amount) private {
        uint256 _inputTokenPrice = _getUsdPrice(_inputToken.priceFeed);
        uint256 _inputAmountUsd = (_amount *
            _inputTokenPrice *
            tokensPrecision[_inputToken.asset].precisionDelta) / PRECISION_18;
        require(_inputAmountUsd >= minBuyAmountUsd, BelowMinBuyAmount());

        uint256 _feeP = _calculateFeeP(_inputAmountUsd, _msgSender(), true);

        uint256 _fee = (_amount * _feeP) / 1e4;
        uint256 _clearAmount = _amount - _fee;

        // calculate llp amount
        uint256 _llpAmount = (((_inputAmountUsd * (1e4 - _feeP)) / 1e4) * PRECISION_18) /
            _llpPrice();
        tokenAmount[_tokenId] += _clearAmount;

        IERC20(_inputToken.asset).safeTransferFrom(_msgSender(), address(this), _clearAmount);
        IERC20(_inputToken.asset).safeTransferFrom(_msgSender(), javBurner, _fee);
        IJavBurner(javBurner).swapAndBurn(_inputToken.asset, _fee);
        IERC20Extended(llpToken).mint(_msgSender(), _llpAmount);

        uint256 _feeAmountUsd = (_fee *
            _inputTokenPrice *
            tokensPrecision[_inputToken.asset].precisionDelta) / PRECISION_18;

        emit BuyLLP(
            _msgSender(),
            _inputToken.asset,
            _tokenId,
            llpToken,
            _amount,
            _llpAmount,
            _fee,
            _feeAmountUsd
        );
    }

    function _sellLLP(uint256 _tokenId, TokenInfo memory _outputToken, uint256 _amount) private {
        uint256 _inputAmountUsd = (_amount *
            _llpPrice() *
            tokensPrecision[llpToken].precisionDelta) / PRECISION_18;

        // calculate tokens amount
        uint256 _tokenUsdPrice = _getUsdPrice(_outputToken.priceFeed);
        uint256 _tokensAmount = (_inputAmountUsd * PRECISION_18) /
            _tokenUsdPrice /
            tokensPrecision[_outputToken.asset].precisionDelta;
        uint256 _feeP = _calculateFeeP(_inputAmountUsd, _msgSender(), false);

        uint256 _fee = (_tokensAmount * _feeP) / 1e4;
        uint256 _clearAmount = _tokensAmount - _fee;
        tokenAmount[_tokenId] -= _tokensAmount;

        IERC20Extended(llpToken).burnFrom(_msgSender(), _amount);
        IERC20(_outputToken.asset).safeTransfer(_msgSender(), _clearAmount);
        IERC20(_outputToken.asset).safeTransfer(javBurner, _fee);
        IJavBurner(javBurner).swapAndBurn(_outputToken.asset, _fee);

        uint256 _feeAmountUsd = (_fee *
            _tokenUsdPrice *
            tokensPrecision[_outputToken.asset].precisionDelta) / PRECISION_18;

        emit SellLLP(
            _msgSender(),
            llpToken,
            _outputToken.asset,
            _tokenId,
            _amount,
            _clearAmount,
            _fee,
            _feeAmountUsd
        );
    }

    function _getUsdPrice(bytes32 _priceFeed) private view returns (uint256) {
        IJavPriceAggregator.Price memory price = priceAggregator.getPriceUnsafe(_priceFeed);
        return PriceUtils.convertToUint(price.price, price.expo, 18);
    }

    function _calculateTotalTvlUsd() private view returns (uint256) {
        uint256 _tvl;
        for (uint8 i = 0; i < tokens.length; ++i) {
            TokenInfo memory _token = tokens[i];
            if (_token.isActive) {
                _tvl += _calculateTvlUsd(i, _token);
            }
        }
        return _tvl;
    }

    function _calculateTvlUsd(
        uint256 _tokenId,
        TokenInfo memory _token
    ) private view returns (uint256) {
        return
            (tokenAmount[_tokenId] *
                _getUsdPrice(_token.priceFeed) *
                tokensPrecision[_token.asset].precisionDelta) / PRECISION_18;
    }

    function _llpPrice() private view returns (uint256) {
        return
            ((_calculateTotalTvlUsd() + rewardsAmountUsd) * PRECISION_18) /
            (IERC20(llpToken).totalSupply() * tokensPrecision[llpToken].precisionDelta);
    }

    function _calculateFeeP(
        uint256 _usdAmount,
        address _user,
        bool _isBuy
    ) private view returns (uint256) {
        uint256 _javFreezerAmount = IJavInfoAggregator(javInfoAggregator).getJavFreezerAmount(
            _user
        );
        uint32 baseFee;
        uint32 reductionFactor;

        if (!_isBuy) {
            for (uint8 i = uint8(javThresholds.length); i > 0; --i) {
                if (_javFreezerAmount >= javThresholds[i - 1] * PRECISION_18) {
                    return sellFees[i - 1];
                }
            }
        }

        for (uint8 i = uint8(usdThresholds.length); i > 0; --i) {
            if (_usdAmount >= usdThresholds[i - 1] * PRECISION_18) {
                baseFee = baseFees[i - 1];
                break; // Exit the loop as we found the correct base fee
            }
        }

        for (uint8 i = uint8(javThresholds.length); i > 0; --i) {
            if (_javFreezerAmount >= javThresholds[i - 1] * PRECISION_18) {
                reductionFactor = reductionFactors[i - 1];
                break; // Exit the loop as the correct reduction factor is found
            }
        }

        return (baseFee * reductionFactor) / 1e4;
    }

    //    function _rebalance() private {
    //        uint256 _totalTvl = _calculateTotalTvlUsd();
    //        RebalanceInfo[] memory rebalanceValues = new RebalanceInfo[](tokens.length);
    //        SwapTokenInfo[] memory swapValues = new SwapTokenInfo[](tokens.length);
    //
    //        // Calculate target and current values for each token
    //        for (uint8 i = 0; i < tokens.length; ++i) {
    //            if (tokens[i].isActive) {
    //                uint256 targetValue = (_totalTvl * tokens[i].targetWeightage) / 100;
    //                uint256 currentValue = _calculateTvlUsd(i, tokens[i]);
    //                bool isSell = currentValue >= targetValue ? true : false;
    //                uint256 excessValue = isSell
    //                    ? currentValue - targetValue
    //                    : targetValue - currentValue;
    //                rebalanceValues[i] = RebalanceInfo({
    //                    tokenId: i,
    //                    targetValue: targetValue,
    //                    currentValue: currentValue,
    //                    excessValue: excessValue > (_totalTvl * 1) / 100 ? excessValue : 0,
    //                    isSell: isSell
    //                });
    //            }
    //        }
    //
    //        // Rebalance tokens by swapping excess tokens for deficit tokens
    //        for (uint256 i = 0; i < tokens.length; i++) {
    //            if (
    //                tokens[i].isActive &&
    //                rebalanceValues[i].excessValue > 0 &&
    //                rebalanceValues[i].isSell
    //            ) {
    //                (swapValues, rebalanceValues) = _calculateSwapAmount(
    //                    i,
    //                    swapValues,
    //                    rebalanceValues
    //                );
    //            }
    //        }
    //        // Swap tokens
    //        for (uint256 i = 0; i < tokens.length; i++) {
    //            if (tokens[i].isActive && swapValues[i].amount > 0) {
    //                _swapToken(
    //                    swapValues[i].tokenIn,
    //                    swapValues[i].tokenOut,
    //                    swapValues[i].amount,
    //                    3000
    //                );
    //            }
    //        }
    //    }
    //
    //    function _calculateSwapAmount(
    //        uint256 _tokenId,
    //        SwapTokenInfo[] memory swapValues,
    //        RebalanceInfo[] memory rebalanceValues
    //    ) private view returns (SwapTokenInfo[] memory, RebalanceInfo[] memory) {
    //        for (uint256 i = 0; i < tokens.length; i++) {
    //            if (
    //                tokens[i].isActive &&
    //                rebalanceValues[i].excessValue > 0 &&
    //                i != _tokenId &&
    //                rebalanceValues[_tokenId].isSell != rebalanceValues[i].isSell
    //            ) {
    //                RebalanceInfo memory rebalanceValue = rebalanceValues[i];
    //                uint256 excessValue;
    //                if (rebalanceValue.excessValue >= rebalanceValues[_tokenId].excessValue) {
    //                    excessValue = rebalanceValues[_tokenId].excessValue;
    //
    //                    rebalanceValues[_tokenId].excessValue = 0;
    //                    rebalanceValues[i].excessValue -= excessValue;
    //                } else {
    //                    excessValue = rebalanceValue.excessValue;
    //
    //                    rebalanceValues[i].excessValue = 0;
    //                    rebalanceValues[_tokenId].excessValue -= excessValue;
    //                }
    //
    //                swapValues = _updateSwapValues(
    //                    swapValues,
    //                    tokens[_tokenId].asset,
    //                    tokens[i].asset,
    //                    (excessValue * 1e18) / _getUsdPrice(tokens[_tokenId].priceFeed)
    //                );
    //
    //                if (rebalanceValues[_tokenId].excessValue == 0) {
    //                    break;
    //                }
    //            }
    //        }
    //        return (swapValues, rebalanceValues);
    //    }
    //
    //    function _updateSwapValues(
    //        SwapTokenInfo[] memory swapValues,
    //        address _tokenIn,
    //        address _tokenOut,
    //        uint256 _amount
    //    ) private pure returns (SwapTokenInfo[] memory) {
    //        bool isPairFound = false;
    //
    //        for (uint256 i = 0; i < swapValues.length; i++) {
    //            if (swapValues[i].tokenIn == _tokenIn && swapValues[i].tokenOut == _tokenOut) {
    //                swapValues[i].amount += _amount;
    //                isPairFound = true;
    //                break;
    //            }
    //        }
    //
    //        if (!isPairFound) {
    //            for (uint256 i = 0; i < swapValues.length; i++) {
    //                if (swapValues[i].tokenIn == address(0)) {
    //                    swapValues[i].tokenIn = _tokenIn;
    //                    swapValues[i].tokenOut = _tokenOut;
    //                    swapValues[i].amount = _amount;
    //                    break;
    //                }
    //            }
    //        }
    //
    //        return swapValues;
    //    }
    //
    //    function _swapToken(
    //        address _tokenIn,
    //        address _tokenOut,
    //        uint256 _amount,
    //        uint256 _poolFee
    //    ) private {
    //        IERC20(_tokenIn).safeDecreaseAllowance(address(swapRouter), 0);
    //        IERC20(_tokenIn).safeIncreaseAllowance(address(swapRouter), _amount);
    //
    //        uint256 _tokenIdIn = _getTokenIdByAddress(_tokenIn);
    //        uint256 _tokenIdOut = _getTokenIdByAddress(_tokenOut);
    //
    //        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    //            tokenIn: _tokenIn,
    //            tokenOut: _tokenOut,
    //            fee: uint24(_poolFee),
    //            recipient: address(this),
    //            amountIn: _amount,
    //            amountOutMinimum: 0,
    //            sqrtPriceLimitX96: 0
    //        });
    //        uint256 _amountOut = swapRouter.exactInputSingle(params);
    //
    //        tokenAmount[_tokenIdIn] -= _amount;
    //        tokenAmount[_tokenIdOut] -= _amountOut;
    //    }
    //
    //    function _getTokenIdByAddress(address _tokenAddress) private view returns (uint256) {
    //        for (uint8 i = 0; i < tokens.length; ++i) {
    //            TokenInfo memory _token = tokens[i];
    //            if (_token.isActive && _token.asset == _tokenAddress) {
    //                return i;
    //            }
    //        }
    //    }
}
