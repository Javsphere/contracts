// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "./IRewardsDistributor.sol";
import "./helpers/IGeneralErrors.sol";

interface IRewardsCollector is IRewardsDistributor, IGeneralErrors {
    error InvalidSwapAmount();

    event SetTokenPoolFee(address token, bool isStable);
    event Withdraw(address indexed token, address indexed recipient, uint256 amount);
    event SetJavBurner(address indexed _address);
}
