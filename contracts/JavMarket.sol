// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./base/BaseUpgradable.sol";

contract JavMarket is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    enum OrderStatus {
        CREATED,
        EXECUTED
    }

    /**
     * @notice Info for update orders
     * @param userAddress: user address
     * @param id: order id
     * @param tradeTokenId: input token id
     * @param tokenId:  Token id for buy
     * @param tokenName: Token name
     * @param buyingType: Buying type (Instant - 1 Limit - 2)
     * @param amount: Amount for buy
     * @param price: Price, ( user only limit order)
     * @param tokenAmount: token amount received
     * @param isBuy: Is buy direction flag (Buy, Sell)
     */
    struct OrderExecutedInfo {
        address userAddress;
        string tokenId;
        string tokenName;
        uint128 id;
        uint128 tradeTokenId;
        uint8 buyingType;
        uint256 amount;
        uint256 price;
        uint256 receiveAmount;
        bool isBuy;
    }

    EnumerableSet.UintSet private _openOrders;
    EnumerableSet.AddressSet private _tokens;

    address public botAddress; // deprecated
    address public treasuryAddress;
    uint256 public totalOrders;
    uint256 public totalAmount;
    uint256 public fee;

    EnumerableSet.AddressSet private _bots;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event AddToken(address indexed _address);
    event RemoveToken(address indexed _address);
    event SetTreasuryAddress(address indexed _address);
    event Withdraw(uint256 indexed _tokenId, address indexed _to, uint256 _amount);
    event SetFee(uint256 indexed _fee);
    event OrderExecuted(
        uint256 indexed _id,
        address indexed _address,
        uint256 _amount,
        uint256 _receiveAmount,
        string _tokenId,
        uint8 _buyingType,
        bool _isBuy,
        uint256 _price,
        string _tokenName,
        JavMarket.OrderStatus _status
    );
    event AddBotAddress(address indexed _address);
    event RemoveBotAddress(address indexed _address);

    modifier onlyBot() {
        require(_bots.contains(msg.sender), "JavMarket: only bot");
        _;
    }

    modifier validTokenId(uint256 _tokenId) {
        require(_tokens.length() > _tokenId, "JavMarket: invalid token id");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _tokensAddresses,
        address _botAddress,
        address _treasuryAddress,
        uint256 _fee
    ) external initializer {
        treasuryAddress = _treasuryAddress;
        fee = _fee;

        for (uint256 i = 0; i < _tokensAddresses.length; ++i) {
            _tokens.add(_tokensAddresses[i]);
        }
        _bots.add(_botAddress);

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setTreasuryAddress(address _address) external onlyAdmin {
        treasuryAddress = _address;

        emit SetTreasuryAddress(_address);
    }

    function setFee(uint256 _fee) external onlyAdmin {
        fee = _fee;

        emit SetFee(_fee);
    }

    function addBotAddress(address _address) external onlyAdmin {
        _bots.add(_address);

        emit AddBotAddress(_address);
    }

    function removeBotAddress(address _address) external onlyAdmin {
        _bots.remove(_address);

        emit RemoveBotAddress(_address);
    }

    function addToken(address _address) external onlyAdmin {
        _tokens.add(_address);

        emit AddToken(_address);
    }

    function removeToken(address _address) external onlyAdmin {
        _tokens.remove(_address);

        emit RemoveToken(_address);
    }

    function getTokens() external view returns (address[] memory) {
        return _tokens.values();
    }

    function getBotsAddresses() external view returns (address[] memory) {
        return _bots.values();
    }

    /**
     * @notice Function to get open orders id
     */
    function getOpenOrders() external view returns (uint256[] memory) {
        return _openOrders.values();
    }

    /**
     * @notice Function to buy diff tokens
     * @param _tradeTokenId: input token id
     * @param _amount: Amount for buy
     * @param _tokenId: Token id for buy
     * @param _buyingType: Buying type
                Instant - 1
                Limit - 2
     * @param _isBuy: Is buy direction flag (Buy, Sell)
     * @param _price: Price, ( user only limit order)
     */
    function tradeToken(
        uint256 _tradeTokenId,
        uint256 _amount,
        string calldata _tokenId,
        uint8 _buyingType,
        bool _isBuy,
        uint256 _price
    ) external whenNotPaused nonReentrant validTokenId(_tradeTokenId) {
        IERC20 token = IERC20(_tokens.at(_tradeTokenId));
        require(token.balanceOf(msg.sender) >= _amount, "JavMarket: invalid amount");
        uint256 feeAmount = (_amount * fee) / 1000;
        uint256 amount = _amount - feeAmount;

        totalAmount += amount;
        totalOrders++;

        token.safeTransferFrom(msg.sender, treasuryAddress, feeAmount);
        token.safeTransferFrom(msg.sender, address(this), amount);

        _openOrders.add(totalOrders);

        emit OrderExecuted(
            totalOrders,
            msg.sender,
            amount,
            0,
            _tokenId,
            _buyingType,
            _isBuy,
            _price,
            "",
            OrderStatus.CREATED
        );
    }

    /**
     * @notice Function to emit OrderExecuted event
     * @param _orderExecutedInfo: order executed info
     */
    function emitOrderExecuted(OrderExecutedInfo[] memory _orderExecutedInfo) external onlyBot {
        for (uint256 i = 0; i < _orderExecutedInfo.length; ++i) {
            require(
                _openOrders.contains(_orderExecutedInfo[i].id),
                "JavMarket: order already executed or not created"
            );
            _openOrders.remove(_orderExecutedInfo[i].id);

            emit OrderExecuted(
                _orderExecutedInfo[i].id,
                _orderExecutedInfo[i].userAddress,
                _orderExecutedInfo[i].amount,
                _orderExecutedInfo[i].receiveAmount,
                _orderExecutedInfo[i].tokenId,
                _orderExecutedInfo[i].buyingType,
                _orderExecutedInfo[i].isBuy,
                _orderExecutedInfo[i].price,
                _orderExecutedInfo[i].tokenName,
                OrderStatus.EXECUTED
            );
        }
    }

    /**
     * @notice Function to withdraw tokens from contract by bot
     * @param _tokenId: tokenId
     * @param _amount: amount
     * @param _withdrawAddress: address for withdraw
     */
    function withdraw(
        uint256 _tokenId,
        uint256 _amount,
        address _withdrawAddress
    ) external validTokenId(_tokenId) onlyBot {
        IERC20 token = IERC20(_tokens.at(_tokenId));
        require(token.balanceOf(address(this)) >= _amount, "JavMarket: invalid amount");

        token.safeTransfer(_withdrawAddress, _amount);

        emit Withdraw(_tokenId, _withdrawAddress, _amount);
    }
}
