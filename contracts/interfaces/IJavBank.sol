// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IJavBank {
    function transfer(address token, address to, uint256 amount) external;
}
