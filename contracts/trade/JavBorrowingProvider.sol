// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/trade/PriceAggregatorUtils.sol";
import "../base/BaseUpgradable.sol";

import "../interfaces/IJavPriceAggregator.sol";
import "../interfaces/IERC20Extended.sol";

contract JavBorrowingProvider is ReentrancyGuardUpgradeable, BaseUpgradable {
    using SafeERC20 for IERC20;
    struct TokenInfo {
        address asset;
        bytes32 priceFeed;
        uint256 targetWeightage;
        bool isActive;
    }

    IJavPriceAggregator public priceAggregator;
    address public jlpToken;
    bytes32 public jlpPriceFeed;
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
        address _jlpToken,
        bytes32 _jlpPriceFeed,
        uint256 _buyFee,
        uint256 _sellFee,
        TokenInfo[] memory _tokens
    ) external initializer {
        priceAggregator = IJavPriceAggregator(_priceAggregator);
        jlpToken = _jlpToken;
        jlpPriceFeed = _jlpPriceFeed;
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

    function _addToken(TokenInfo memory tokenInfo) private {
        tokens.push(tokenInfo);

        emit AddToken(tokenInfo);
    }

    function _buyJLP(TokenInfo memory _inputToken, uint256 _amount) private {
        uint256 _inputAmountUsd = (_amount * _getUsdPrice(_inputToken.priceFeed)) / 1e18;
        // calculate jlp amount
        uint256 _fee = (_inputAmountUsd * buyFee) / 1e4;
        uint256 _jlpUsdPrice = _getUsdPrice(jlpPriceFeed);
        uint256 _jlpAmount = ((_inputAmountUsd - _fee) * 1e18) / _jlpUsdPrice;

        IERC20(_inputToken.asset).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Extended(jlpToken).mint(msg.sender, _jlpAmount);

        emit BuyJLP(msg.sender, _jlpAmount);
    }

    function _sellJLP(TokenInfo memory _outputToken, uint256 _amount) private {
        uint256 _inputAmountUsd = (_amount * _getUsdPrice(jlpPriceFeed)) / 1e18;
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
}
