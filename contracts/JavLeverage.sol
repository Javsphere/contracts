// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IStateRelayer.sol";
import "./interfaces/IJavBank.sol";
import "./base/BaseUpgradable.sol";

contract JavLeverage is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    struct TokenInfo {
        address tokenAddress;
        string tokenPair;
    }

    /**
     * @notice Info for orders
     * @param id: order id
     * @param pairId: pair id
     * @param leverageTokenId: leverage token id
     * @param side:order side buy or sell
     * @param amount: order amount
     * @param price: price
     * @param date: order data
     * @param filled: filled amount
     * @param closed: is order closed
     */
    struct Order {
        uint64 id;
        uint64 tokenId;
        uint64 leverageTokenId;
        uint64 leverage;
        address trader;
        Side side;
        uint256 userAmount;
        uint256 amount;
        uint256 startPrice;
        uint256 endPrice;
        uint256 date;
        bool closed;
    }

    enum Side {
        SHORT,
        LONG
    }

    uint256 private _leverageLockAmount;
    uint256 public fee;
    address public stateRelayer;
    address public javBank;
    mapping(address => mapping(uint256 => uint256)) public balances;
    mapping(address => mapping(uint256 => uint256)) public inUseBalances;
    mapping(uint256 => Order[]) public orders;
    mapping(address => mapping(uint256 => bool)) public activeOrder;
    mapping(uint256 => EnumerableSet.UintSet) private _openOrders;
    TokenInfo[] public tokens;

    /* ========== EVENTS ========== */
    event SetStateRelayer(address indexed _address);
    event SetJavBank(address indexed _address);
    event SetFee(uint256 indexed fee);
    event AddToken(address indexed _address, uint256 index);
    event Deposit(address indexed user, uint256 indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed token, uint256 amount);
    event OpenPosition(
        address indexed user,
        uint256 indexed token,
        uint256 indexed orderId,
        Side side
    );
    event ClosePosition(address indexed user, uint256 indexed token, uint256 indexed orderId);
    event LiquidatePosition(uint256 indexed token, uint256 indexed orderId);
    event UpdatePosition(
        address indexed user,
        uint256 indexed token,
        uint256 indexed orderId,
        uint256 amount
    );

    modifier validOrder(uint128 _tokenId, uint128 _orderId) {
        require(_openOrders[_tokenId].contains(_orderId), "JavLeverage: invalid order id");
        _;
    }

    modifier validTokenId(uint256 index) {
        require(index < tokens.length, "JavLeverage: invalid token id");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _stateRelayer,
        address _javBank,
        uint256 _fee
    ) external initializer {
        stateRelayer = _stateRelayer;
        javBank = _javBank;
        fee = _fee;

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setStateRelayer(address _address) external onlyAdmin {
        stateRelayer = _address;

        emit SetStateRelayer(_address);
    }

    function setJavBank(address _address) external onlyAdmin {
        javBank = _address;

        emit SetJavBank(_address);
    }

    function setFee(uint256 _fee) external onlyAdmin {
        fee = _fee;

        emit SetFee(_fee);
    }

    function addToken(address _address, string memory _tokenPair) external onlyAdmin {
        tokens.push(TokenInfo({tokenAddress: _address, tokenPair: _tokenPair}));

        emit AddToken(_address, tokens.length - 1);
    }

    /**
     * @notice Function to get token price in usd
     * @param _tokenId token id
     */
    function getTokenPrice(
        uint256 _tokenId
    ) external view validTokenId(_tokenId) returns (uint256) {
        return _getPrice(tokens[_tokenId].tokenPair);
    }

    /**
     * @notice Function to get orders by token and direction
     * @param _tokenId token id
     */
    function getOrders(
        uint256 _tokenId
    ) external view validTokenId(_tokenId) returns (Order[] memory) {
        uint256[] memory values = _openOrders[_tokenId].values();
        Order[] memory _orders = new Order[](values.length);
        for (uint256 i = 0; i < values.length; ++i) {
            _orders[i] = orders[_tokenId][values[i]];
        }
        return _orders;
    }

    /**
     * @notice Function to deposit tokens
     * @param _tokenId token id
     * @param _amount token amount
     */
    function deposit(
        uint256 _tokenId,
        uint256 _amount
    ) external validTokenId(_tokenId) nonReentrant {
        IERC20 token = IERC20(tokens[_tokenId].tokenAddress);
        require(token.balanceOf(msg.sender) >= _amount, "JavTrading: invalid amount for deposit");

        balances[msg.sender][_tokenId] += _amount;

        token.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _tokenId, _amount);
    }

    /**
     * @notice Function to withdraw tokens
     * @param _tokenId token id
     * @param _amount token amount
     */
    function withdraw(uint256 _tokenId, uint256 _amount) external validTokenId(_tokenId) {
        require(balances[msg.sender][_tokenId] >= _amount, "JavTrading: invalid withdraw amount");
        require(!activeOrder[msg.sender][_tokenId], "JavLeverage: active order");
        IERC20 token = IERC20(tokens[_tokenId].tokenAddress);

        balances[msg.sender][_tokenId] -= _amount;

        token.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _tokenId, _amount);
    }

    /**
     * @notice Function to open leverage position
     * @param _tokenId token id
     * @param _leverage leverage token id
     * @param _leverage leverage
     * @param _amount amount
     * @param _side Side short/long
     */
    function openPosition(
        uint64 _tokenId,
        uint64 _leverageTokenId,
        uint64 _leverage,
        uint256 _amount,
        Side _side
    ) external validTokenId(_tokenId) nonReentrant {
        require(!activeOrder[msg.sender][_tokenId], "JavLeverage: order already activated");
        require(
            balances[msg.sender][_tokenId] >= _amount,
            "JavLeverage: invalid amount for open position"
        );
        uint256 borrowAmount = _amount * (_leverage - 1);

        require(
            IERC20(tokens[_tokenId].tokenAddress).balanceOf(javBank) >=
                borrowAmount + _leverageLockAmount,
            "JavLeverage: invalid amount for borrow"
        );

        _leverageLockAmount += borrowAmount;

        Order[] storage _orders = orders[_tokenId];
        uint64 orderId = uint64(_orders.length);
        uint256 _price = _getPrice(tokens[_leverageTokenId].tokenPair);

        _orders.push(
            Order({
                id: orderId,
                tokenId: _tokenId,
                leverageTokenId: _leverageTokenId,
                trader: msg.sender,
                side: _side,
                leverage: _leverage,
                userAmount: _amount,
                amount: _amount * _leverage,
                startPrice: _price,
                endPrice: 0,
                date: block.timestamp,
                closed: false
            })
        );

        balances[msg.sender][_tokenId] -= _amount;
        inUseBalances[msg.sender][_tokenId] += _amount;

        activeOrder[msg.sender][_tokenId] = true;
        _openOrders[_tokenId].add(orderId);

        emit OpenPosition(msg.sender, _tokenId, orderId, _side);
    }

    /**
     * @notice Function to close leverage position
     * @param _tokenId token id
     * @param _orderId order Id
     */
    function closePosition(
        uint128 _tokenId,
        uint128 _orderId
    ) external validTokenId(_tokenId) validOrder(_tokenId, _orderId) nonReentrant {
        require(activeOrder[msg.sender][_tokenId], "JavLeverage: order already deactivated");
        Order storage order = orders[_tokenId][_orderId];
        require(order.trader == msg.sender, "JavLeverage: no access to close this order");

        address token = tokens[_tokenId].tokenAddress;
        uint256 _price = _getPrice(tokens[order.leverageTokenId].tokenPair);
        _validatePositionPrice(_price, order);

        uint256 _priceDiff = _calculatePriceDiff(_price, order);
        uint256 profit = ((order.amount * _priceDiff) / 1e18) - order.amount;
        uint256 feeAmount = (profit * fee) / 100;
        uint256 userAmount = profit - feeAmount;

        order.closed = true;
        order.endPrice = _price;

        _leverageLockAmount -= (order.amount - order.userAmount);
        balances[order.trader][_tokenId] += (userAmount + order.userAmount);
        inUseBalances[order.trader][_tokenId] -= order.userAmount;

        IERC20(token).safeTransfer(javBank, feeAmount);
        IJavBank(javBank).transfer(token, address(this), userAmount);

        activeOrder[msg.sender][_tokenId] = false;
        _openOrders[_tokenId].remove(_orderId);

        emit ClosePosition(msg.sender, _tokenId, _orderId);
    }

    /**
     * @notice Function to update leverage position
     * @param _tokenId token id
     * @param _orderId order Id
     * @param _amount amount
     */
    function updatePosition(
        uint128 _tokenId,
        uint128 _orderId,
        uint256 _amount
    ) external validTokenId(_tokenId) validOrder(_tokenId, _orderId) nonReentrant {
        require(activeOrder[msg.sender][_tokenId], "JavLeverage: order already deactivated");
        Order storage order = orders[_tokenId][_orderId];
        require(order.trader == msg.sender, "JavLeverage: no access to close this order");
        require(balances[msg.sender][order.tokenId] >= _amount, "JavLeverage: invalid amount");

        order.userAmount += _amount;

        balances[msg.sender][_tokenId] -= _amount;
        inUseBalances[msg.sender][_tokenId] += _amount;

        emit UpdatePosition(msg.sender, _tokenId, _orderId, _amount);
    }

    function liquidatePosition(
        uint128 _tokenId,
        uint128 _orderId
    ) external validTokenId(_tokenId) validOrder(_tokenId, _orderId) {
        Order storage order = orders[_tokenId][_orderId];
        uint256 _price = _getPrice(tokens[order.leverageTokenId].tokenPair);

        _validatePositionPrice(_price, order);

        order.closed = true;
        order.endPrice = _price;

        _leverageLockAmount -= (order.amount - order.userAmount);
        inUseBalances[msg.sender][_tokenId] -= order.userAmount;
        IERC20(tokens[_tokenId].tokenAddress).safeTransfer(javBank, order.userAmount);

        activeOrder[order.trader][_tokenId] = false;
        _openOrders[_tokenId].remove(_orderId);

        emit LiquidatePosition(_tokenId, _orderId);
    }

    function _getPrice(string memory _pair) private view returns (uint256) {
        (, IStateRelayer.DEXInfo memory dex) = IStateRelayer(stateRelayer).getDexPairInfo(_pair);

        return dex.primaryTokenPrice;
    }

    function _calculatePriceDiff(
        uint256 _price,
        Order memory order
    ) private pure returns (uint256) {
        if (order.side == Side.LONG) {
            return (_price * 1e18) / order.startPrice;
        } else {
            return (order.startPrice * 1e18) / _price;
        }
    }

    function _validatePositionPrice(uint256 _price, Order memory order) private pure {
        if (order.side == Side.LONG) {
            require(_price >= order.startPrice, "JavLeverage: error when liquidate position");
        } else {
            require(_price <= order.startPrice, "JavLeverage: error when liquidate position");
        }
    }
}
