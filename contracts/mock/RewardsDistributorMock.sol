// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "../interfaces/IRewardsDistributor.sol";

contract RewardsDistributorMock is IRewardsDistributor {
    function distributeRewards(address[] memory _tokens) external {}
}
