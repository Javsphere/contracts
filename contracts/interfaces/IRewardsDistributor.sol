// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IRewardsDistributor {
    function distributeRewards(address[] memory _tokens) external;
}
