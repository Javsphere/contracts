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

    enum OrderStatus {
        CREATED,
        EXECUTED
    }

    /**
     * @notice Info for update orders
     * @param userAddress: user address
     * @param id: order id
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
        uint8 buyingType;
        uint256 amount;
        uint256 price;
        uint256 receiveAmount;
        bool isBuy;
    }

    EnumerableSet.UintSet private _openOrders;

    IERC20 public dusdToken;
    address public botAddress;
    address public treasuryAddress;
    uint256 public totalOrders;
    uint256 public totalAmount;
    uint256 public fee;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event SetTreasuryAddress(address indexed _address);
    event Withdraw(address indexed _to, uint256 _amount);
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

    modifier onlyBot() {
        require(msg.sender == botAddress, "JavMarket: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _botAddress,
        address _treasuryAddress,
        uint256 _fee
    ) external initializer {
        botAddress = _botAddress;
        treasuryAddress = _treasuryAddress;
        dusdToken = IERC20(_tokenAddress);
        fee = _fee;

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setBotAddress(address _address) external onlyAdmin {
        botAddress = _address;

        emit SetBotAddress(_address);
    }

    function setTreasuryAddress(address _address) external onlyAdmin {
        treasuryAddress = _address;

        emit SetTreasuryAddress(_address);
    }

    function setFee(uint256 _fee) external onlyAdmin {
        fee = _fee;

        emit SetFee(_fee);
    }

    /**
     * @notice Function to get open orders id
     */
    function getOpenOrders() external view returns (uint256[] memory) {
        return _openOrders.values();
    }

    /**
     * @notice Function to buy diff tokens
     * @param _amount: Amount for buy
     * @param _tokenId: Token id for buy
     * @param _buyingType: Buying type
                Instant - 1
                Limit - 2
     * @param _isBuy: Is buy direction flag (Buy, Sell)
     * @param _price: Price, ( user only limit order)
     */
    function buyToken(
        uint256 _amount,
        string calldata _tokenId,
        uint8 _buyingType,
        bool _isBuy,
        uint256 _price
    ) external whenNotPaused nonReentrant {
        require(dusdToken.balanceOf(msg.sender) >= _amount, "JavMarket: invalid amount");
        uint256 feeAmount = (_amount * fee) / 1000;
        uint256 amount = _amount - feeAmount;

        totalAmount += amount;
        totalOrders++;

        dusdToken.safeTransferFrom(msg.sender, treasuryAddress, feeAmount);
        dusdToken.safeTransferFrom(msg.sender, address(this), amount);

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
     * @notice Function to withdraw dusd tokens from contract by bot
     * @param _amount: amount
     */
    function withdraw(uint256 _amount) external onlyBot {
        require(dusdToken.balanceOf(address(this)) >= _amount, "JavMarket: invalid amount");

        dusdToken.safeTransfer(botAddress, _amount);

        emit Withdraw(botAddress, _amount);
    }
}
