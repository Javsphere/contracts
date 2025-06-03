// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IJavEscrow {
    struct Order {
        uint256 orderId;
        address token0;
        address token1;
        address seller;
        address buyer;
        uint256 token0Amount; //token precision
        uint256 token1Amount; //token precision
        bool isActive;
    }

    event AddAvailableToken(address indexed _address);
    event RemoveAvailableToken(address indexed _address);
    event SetPlaceOrderFee(uint32 _fee);
    event ClaimFee(address indexed _wallet, uint256 _fee);
    event OrderPlaced(uint256 indexed _id, Order _order);
    event CancelOrder(uint256 indexed _id, Order _order);
    event AcceptOrder(uint256 indexed _id, Order _order);
}
