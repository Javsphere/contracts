// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/trade/PriceAggregatorUtils.sol";
import "../base/BaseUpgradable.sol";

import "../interfaces/IJavPriceAggregator.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/ISwapRouter.sol";

contract JavLiquidityProvider is ReentrancyGuardUpgradeable, BaseUpgradable {
    using SafeERC20 for IERC20;
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

    IJavPriceAggregator public priceAggregator;
    ISwapRouter public swapRouter;
    address public jlpToken;
    uint256 public buyFee; // * 1e4
    uint256 public sellFee; // * 1e4

    TokenInfo[] public tokens;

    /* ========== EVENTS ========== */
    event AddToken(TokenInfo tokenInfo);
    event BuyJLP(address indexed user, uint256 amount);
    event SellJLP(address indexed user, uint256 amount);

    modifier validToken(uint256 _tokenId) {
        require(_tokenId < tokens.length, "JavBorrowingProvider: Invalid token");
        require(tokens[_tokenId].isActive, "JavBorrowingProvider: Token is inactive");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _priceAggregator,
        address _swapRouter,
        address _jlpToken,
        uint256 _buyFee,
        uint256 _sellFee,
        TokenInfo[] memory _tokens
    ) external initializer {
        priceAggregator = IJavPriceAggregator(_priceAggregator);
        swapRouter = ISwapRouter(_swapRouter);
        jlpToken = _jlpToken;
        buyFee = _buyFee;
        sellFee = _sellFee;

        for (uint8 i = 0; i < _tokens.length; ++i) {
            _addToken(_tokens[i]);
        }

        __Base_init();
        __ReentrancyGuard_init();
    }

    /**
     * @notice Function to buy JLP token
     * @param _inputToken: input token id for buy
     * @param _amount: amount
     */
    function buyJLP(
        uint256 _inputToken,
        uint256 _amount
    ) external nonReentrant whenNotPaused validToken(_inputToken) {
        TokenInfo memory _token = tokens[_inputToken];
        require(
            IERC20(_token.asset).balanceOf(msg.sender) >= _amount,
            "JavBorrowingProvider: invalid balance for buy"
        );

        _buyJLP(_token, _amount);
    }

    /**
     * @notice Function to sell JLP token
     * @param _outputToken: input token id for buy
     * @param _amount: amount
     */
    function sellJLP(
        uint256 _outputToken,
        uint256 _amount
    ) external nonReentrant whenNotPaused validToken(_outputToken) {
        TokenInfo memory _token = tokens[_outputToken];
        require(
            IERC20(jlpToken).balanceOf(msg.sender) >= _amount,
            "JavBorrowingProvider: invalid balance for sell"
        );

        _sellJLP(_token, _amount);
    }

    function rebalanceTokens() external {
        _rebalance();
    }

    function tvl() external view returns (uint256) {
        return _calculateTotalTvlUsd();
    }

    function jlpPrice() external view returns (uint256) {
        return _jlpPrice();
    }

    function _addToken(TokenInfo memory tokenInfo) private {
        tokens.push(tokenInfo);

        emit AddToken(tokenInfo);
    }

    function _buyJLP(TokenInfo memory _inputToken, uint256 _amount) private {
        uint256 _inputAmountUsd = (_amount * _getUsdPrice(_inputToken.priceFeed)) / 1e18;
        // calculate jlp amount
        uint256 _fee = (_inputAmountUsd * buyFee) / 1e4;
        uint256 _jlpAmount = ((_inputAmountUsd - _fee) * 1e18) / _jlpPrice();

        IERC20(_inputToken.asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Extended(jlpToken).mint(msg.sender, _jlpAmount);

        emit BuyJLP(msg.sender, _jlpAmount);
    }

    function _sellJLP(TokenInfo memory _outputToken, uint256 _amount) private {
        uint256 _inputAmountUsd = (_amount * _jlpPrice()) / 1e18;
        // calculate tokens amount
        uint256 _fee = (_inputAmountUsd * sellFee) / 1e4;
        uint256 _tokenUsdPrice = _getUsdPrice(_outputToken.priceFeed);
        uint256 _tokensAmount = ((_inputAmountUsd - _fee) * 1e18) / _tokenUsdPrice;

        IERC20Extended(jlpToken).burnFrom(msg.sender, _amount);
        IERC20(_outputToken.asset).safeTransfer(msg.sender, _tokensAmount);

        emit SellJLP(msg.sender, _amount);
    }

    function _getUsdPrice(bytes32 _priceFeed) private view returns (uint256) {
        IJavPriceAggregator.Price memory price = priceAggregator.getPrice(_priceFeed);
        return PriceUtils.convertToUint(price.price, price.expo, 18);
    }

    function _calculateTotalTvlUsd() private view returns (uint256) {
        uint256 _tvl;
        for (uint8 i = 0; i < tokens.length; ++i) {
            TokenInfo memory _token = tokens[i];
            if (_token.isActive) {
                _tvl += _calculateTvlUsd(_token);
            }
        }
        return _tvl;
    }

    function _calculateTvlUsd(TokenInfo memory _token) private view returns (uint256) {
        return
            (IERC20(_token.asset).balanceOf(address(this)) * _getUsdPrice(_token.priceFeed)) / 1e18;
    }

    function _jlpPrice() private view returns (uint256) {
        return (_calculateTotalTvlUsd() * 1e18) / IERC20(jlpToken).totalSupply();
    }

    function _rebalance() private {
        uint256 _totalTvl = _calculateTotalTvlUsd();
        RebalanceInfo[] memory rebalanceValues = new RebalanceInfo[](tokens.length);
        SwapTokenInfo[] memory swapValues = new SwapTokenInfo[](tokens.length);

        // Calculate target and current values for each token
        for (uint8 i = 0; i < tokens.length; ++i) {
            if (tokens[i].isActive) {
                uint256 targetValue = (_totalTvl * tokens[i].targetWeightage) / 100;
                uint256 currentValue = _calculateTvlUsd(tokens[i]);
                bool isSell = currentValue >= targetValue ? true : false;
                uint256 excessValue = isSell
                    ? currentValue - targetValue
                    : targetValue - currentValue;
                rebalanceValues[i] = RebalanceInfo({
                    tokenId: i,
                    targetValue: targetValue,
                    currentValue: currentValue,
                    excessValue: excessValue > (_totalTvl * 1) / 100 ? excessValue : 0,
                    isSell: isSell
                });
            }
        }

        // Rebalance tokens by swapping excess tokens for deficit tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (
                tokens[i].isActive &&
                rebalanceValues[i].excessValue > 0 &&
                rebalanceValues[i].isSell
            ) {
                (swapValues, rebalanceValues) = _calculateSwapAmount(
                    i,
                    swapValues,
                    rebalanceValues
                );
            }
        }
        // Swap tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].isActive && swapValues[i].amount > 0) {
                _swapToken(
                    swapValues[i].tokenIn,
                    swapValues[i].tokenOut,
                    swapValues[i].amount,
                    3000
                );
            }
        }
    }

    function _calculateSwapAmount(
        uint256 _tokenId,
        SwapTokenInfo[] memory swapValues,
        RebalanceInfo[] memory rebalanceValues
    ) private view returns (SwapTokenInfo[] memory, RebalanceInfo[] memory) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (
                tokens[i].isActive &&
                rebalanceValues[i].excessValue > 0 &&
                i != _tokenId &&
                rebalanceValues[_tokenId].isSell != rebalanceValues[i].isSell
            ) {
                RebalanceInfo memory rebalanceValue = rebalanceValues[i];
                uint256 excessValue;
                if (rebalanceValue.excessValue >= rebalanceValues[_tokenId].excessValue) {
                    excessValue = rebalanceValues[_tokenId].excessValue;

                    rebalanceValues[_tokenId].excessValue = 0;
                    rebalanceValues[i].excessValue -= excessValue;
                } else {
                    excessValue = rebalanceValue.excessValue;

                    rebalanceValues[i].excessValue = 0;
                    rebalanceValues[_tokenId].excessValue -= excessValue;
                }

                swapValues = _updateSwapValues(
                    swapValues,
                    tokens[_tokenId].asset,
                    tokens[i].asset,
                    (excessValue * 1e18) / _getUsdPrice(tokens[_tokenId].priceFeed)
                );

                if (rebalanceValues[_tokenId].excessValue == 0) {
                    break;
                }
            }
        }
        return (swapValues, rebalanceValues);
    }

    function _updateSwapValues(
        SwapTokenInfo[] memory swapValues,
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) private pure returns (SwapTokenInfo[] memory) {
        bool isPairFound = false;

        for (uint256 i = 0; i < swapValues.length; i++) {
            if (swapValues[i].tokenIn == _tokenIn && swapValues[i].tokenOut == _tokenOut) {
                swapValues[i].amount += _amount;
                isPairFound = true;
                break;
            }
        }

        if (!isPairFound) {
            for (uint256 i = 0; i < swapValues.length; i++) {
                if (swapValues[i].tokenIn == address(0)) {
                    swapValues[i].tokenIn = _tokenIn;
                    swapValues[i].tokenOut = _tokenOut;
                    swapValues[i].amount = _amount;
                    break;
                }
            }
        }

        return swapValues;
    }

    function _swapToken(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        uint256 _poolFee
    ) private {
        IERC20(_tokenIn).safeDecreaseAllowance(address(swapRouter), 0);
        IERC20(_tokenIn).safeIncreaseAllowance(address(swapRouter), _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: uint24(_poolFee),
            recipient: address(this),
            amountIn: _amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactInputSingle(params);
    }
}
