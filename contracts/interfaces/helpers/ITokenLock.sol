// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IGeneralErrors.sol";

interface ITokenLock is IGeneralErrors {
    function lockTokens(address _from, uint256 _amount) external;

    event SetTokenAddress(address indexed _address);
    event SetMigratorAddress(address indexed _address);
    event LockTokens(address indexed sender, uint256 amount);
}
