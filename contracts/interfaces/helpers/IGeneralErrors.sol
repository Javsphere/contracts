// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * @custom:version 8
 * @dev Interface for errors potentially used in all libraries (general names)
 */
interface IGeneralErrors {
    error InvalidAmount();
    error InvalidAddresses();
    error InvalidInputLength();
    error WrongParams();
    error WrongLength();
    error WrongIndex();
    error Overflow();
    error ZeroAddress();
    error ZeroValue();
    error AlreadyExists();
    error DoesntExist();
    error NotAllowed();
}
