// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/helpers/IGeneralErrors.sol";
import "./interfaces/IJavEscrow.sol";
import "./base/BaseUpgradable.sol";

contract JavEscrow is IJavEscrow, IGeneralErrors, BaseUpgradable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _availableTokens;
    uint32 public placeOrderFee; //1e4
    uint256 public lastOrderId;
    mapping(address => uint256) public fees;
    mapping(uint256 => Order) public orders;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initializer function called when this contract is deployed
    function initialize(
        address[] memory availableTokens,
        uint32 _placeOrderFee
    ) external initializer {
        for (uint8 i = 0; i < availableTokens.length; ++i) {
            _availableTokens.add(availableTokens[i]);
        }
        placeOrderFee = _placeOrderFee;
        __Base_init();
    }

    function getAvailableTokens() external view returns (address[] memory) {
        return _availableTokens.values();
    }

    function addAvailableToken(address _address) external onlyAdmin {
        _availableTokens.add(_address);

        emit AddAvailableToken(_address);
    }

    function removeAvailableToken(address _address) external onlyAdmin {
        _availableTokens.remove(_address);

        emit RemoveAvailableToken(_address);
    }

    function setPlaceOrderFee(uint32 _placeOrderFee) external onlyAdmin {
        placeOrderFee = _placeOrderFee;

        emit SetPlaceOrderFee(_placeOrderFee);
    }

    function claimFee(address _token, address _wallet) external onlyAdmin {
        uint256 _fee = fees[_token];

        fees[_token] = 0;

        IERC20(_token).safeTransfer(_wallet, _fee);

        emit ClaimFee(_wallet, _fee);
    }

    function placeOrder(Order memory _order) external {
        require(_order.orderId == lastOrderId, IGeneralErrors.WrongIndex());
        require(_order.isActive, IGeneralErrors.WrongParams());
        require(_order.seller == _msgSender(), IGeneralErrors.NotAllowed());
        require(
            _availableTokens.contains(_order.token0) && _availableTokens.contains(_order.token1),
            IGeneralErrors.InvalidAddresses()
        );

        uint256 feeAmount = (_order.token0Amount * placeOrderFee) / 1e4;

        IERC20(_order.token0).safeTransferFrom(
            _msgSender(),
            address(this),
            _order.token0Amount + feeAmount
        );

        fees[_order.token0] += feeAmount;
        orders[lastOrderId] = _order;
        lastOrderId++;

        emit OrderPlaced(lastOrderId - 1, _order);
    }

    function cancelOrder(uint256 _orderId) external {
        Order memory _order = orders[_orderId];
        require(_order.isActive, IGeneralErrors.DoesntExist());
        require(_order.seller == _msgSender(), IGeneralErrors.NotAllowed());

        IERC20(_order.token0).safeTransfer(_msgSender(), _order.token0Amount);
        _order.isActive = false;
        orders[_orderId] = _order;

        emit CancelOrder(_orderId, _order);
    }

    function acceptOrder(uint256 _orderId) external {
        Order memory _order = orders[_orderId];
        require(_order.isActive, IGeneralErrors.DoesntExist());

        IERC20(_order.token0).safeTransfer(_msgSender(), _order.token0Amount);
        IERC20(_order.token1).safeTransferFrom(_msgSender(), _order.seller, _order.token1Amount);

        _order.isActive = false;
        orders[_orderId] = _order;

        emit AcceptOrder(_orderId, _order);
    }
}
