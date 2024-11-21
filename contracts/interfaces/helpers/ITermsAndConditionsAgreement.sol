// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface ITermsAndConditionsAgreement {
    function hasAgreed(address user) external view returns (bool);
}
