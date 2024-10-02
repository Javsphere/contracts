// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IGeneralErrors.sol";

interface ITokenLock is IGeneralErrors {
    function lockTokens(uint256 _amount) external;

    event LockTokens(address indexed sender, uint256 amount);
}
