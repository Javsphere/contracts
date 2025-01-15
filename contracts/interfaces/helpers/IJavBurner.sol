// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IGeneralErrors.sol";
import "../IRouter.sol";

interface IJavBurner is IGeneralErrors {
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
    event SetJavAddress(address indexed _address);
    event SetSwapRouterAddress(address indexed _address);
    event SetSwapRoute(address indexed _address, IRouter.Route[] route);
    event SwapAndBurn(address indexed token, uint256 swapAmount, uint256 burnAmount);
}
