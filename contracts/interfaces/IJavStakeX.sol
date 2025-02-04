// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./helpers/IGeneralErrors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IJavStakeX is IGeneralErrors {
    /**
     * @notice Info for update user investment/withdraw info
     * @param user: user address
     * @param amount: investment amount
     */
    struct PoolInfo {
        IERC20 baseToken;
        IERC20 rewardToken;
        uint256 totalShares;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 rewardsAmount;
        uint256 rewardsPerShare;
        uint256 minStakeAmount;
    }

    struct UserInfo {
        uint256 shares;
        uint256 blockRewardDebt;
        uint256 productsRewardDebt;
        uint256 totalClaims;
    }

    struct PoolFee {
        uint64 depositFee; //* 1e4
        uint64 withdrawFee; //* 1e4
        uint64 claimFee; //* 1e4
    }

    struct TokenPrecisionInfo {
        uint128 precision;
        uint128 precisionDelta;
    }

    function userShares(uint256 _pid, address _user) external view returns (uint256);

    function addRewards(uint256 _pid, uint256 _amount) external;

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
    event SetPoolFee(uint256 _pid, PoolFee _poolFee);
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
    event SetVoteAddress(address indexed _address);

    error WrongPool();
    error ActiveVoteProposal();
}
