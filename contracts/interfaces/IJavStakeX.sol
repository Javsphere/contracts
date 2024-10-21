// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./helpers/IGeneralErrors.sol";

interface IJavStakeX is IGeneralErrors {
    function userShares(uint256 _pid, address _user) external view returns (uint256);

    function addRewards(uint256 _pid, uint256 _amount) external;

    function burnTokens(uint256 _pid, address _holder) external;

    function makeMigration(uint256 _pid, uint256 _amount, address _holder) external;

    event AddPool(
        address indexed _baseToken,
        address indexed _rewardToken,
        uint128 _minStakeAmount
    );
    event UpdatePool(
        uint256 indexed _pid,
        uint256 _totalShares,
        uint256 _rewardsAmount,
        uint256 _rewardsPerShare
    );
    event SetPoolInfo(uint256 _pid, uint256 _lastRewardBlock, uint256 _accRewardPerShare);
    event SetRewardsDistributorAddress(address indexed _address);
    event Stake(address indexed _address, uint256 indexed _pid, uint256 _amount);
    event Unstake(address indexed _address, uint256 _pid, uint256 _amount);
    event Claim(address indexed _token, address indexed _user, uint256 _amount);
    event AddRewards(uint256 indexed pid, uint256 amount);
    event Burn(address _token, uint256 _amount);
    event SetInfinityPassPercent(uint256 indexed _percent);
    event SetInfinityPass(address indexed _address);
    event SetMigratorAddress(address indexed _address);
    event BurnTokens(uint256 indexed pid, address indexed holder, uint256 amount);

    error WrongPool();
}
