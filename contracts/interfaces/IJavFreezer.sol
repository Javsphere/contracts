// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./helpers/IGeneralErrors.sol";

interface IJavFreezer is IGeneralErrors {
    /**
     * @notice Info for each staking by ID
     * One Address can have many Deposits with different periods. Unlimited Amount.
     * depositTokens = amount of tokens for exact deposit.
     * stakePeriod = Locking Period - from 3 months to 30 months. value is integer
     * depositTimestamp = timestamp of deposit
     * withdrawalTimestamp = Timestamp when user can withdraw his locked tokens
     * is_finished = checks if user has already withdrawn tokens
     */
    struct UserDeposit {
        uint256 depositTokens;
        uint256 stakePeriod;
        uint256 depositTimestamp;
        uint256 withdrawalTimestamp;
        uint256 rewardsClaimed;
        uint256 rewardDebt;
        bool is_finished;
    }

    function pendingReward(
        uint256 _pid,
        uint256 _depositId,
        address _user
    ) external view returns (uint256);

    function getUserLastDepositId(uint256 _pid, address _user) external view returns (uint256);

    function userDepositTokens(uint256 _pid, address _user) external view returns (uint256);

    function userDeposit(
        address _user,
        uint256 _pid,
        uint256 _id
    ) external view returns (UserDeposit memory);

    function depositVesting(
        address _holder,
        uint256 _pid,
        uint256 _amount,
        uint256 _depositTimestamp,
        uint256 _withdrawalTimestamp,
        uint256 _lockId
    ) external;

    function withdrawVesting(
        address _holder,
        uint256 _pid,
        uint256 _depositId,
        uint256 _amount
    ) external;

    function addRewards(uint256 _pid, uint256 _amount) external;

    function burnTokens(uint256 _pid, address _holder) external;

    function makeMigration(
        uint256 _pid,
        address _holder,
        UserDeposit[] memory _userDeposits
    ) external;

    event SetPoolInfo(uint256 _pid, uint256 _lastRewardBlock, uint256 _accRewardPerShare);
    event AddPool(
        address indexed _baseToken,
        address indexed _rewardToken,
        uint256 _lastRewardBlock,
        uint256 _accRewardPerShare
    );
    event SetLockPeriod(uint256 indexed _lockId, uint256 _duration);
    event SetLockPeriodMultiplier(uint256 indexed _lockId, uint256 _multiplier);
    event SetVestingAddress(address indexed _address);
    event SetRewardsDistributorAddress(address indexed _address);
    event ClaimUserReward(
        address indexed user,
        uint256 amount,
        uint256 indexed pid,
        uint256 indexed period
    );
    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 indexed pid,
        uint256 indexed period,
        uint256 depositTimestamp,
        uint256 withdrawalTimestamp
    );
    event Withdraw(
        address indexed user,
        uint256 amount,
        uint256 indexed pid,
        uint256 indexed period
    );
    event AddRewards(uint256 indexed pid, uint256 amount);
    event Burn(address _token, uint256 _amount);
    event SetInfinityPassPercent(uint256 indexed _percent);
    event SetInfinityPass(address indexed _address);
    event SetMigratorAddress(address indexed _address);
    event BurnTokens(uint256 indexed pid, address indexed holder, uint256 lockId, uint256 amount);

    error WrongPool();
    error WrongLockPeriod();
    error AlreadyFinished();
    error PeriodNotEnded();
}
