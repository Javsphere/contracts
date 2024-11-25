// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IERC20Extended.sol";
import "../base/BaseUpgradable.sol";
import "./IJavStakeX.sol";
import "./RewardRateConfigurable.sol";

contract JavStakeX is
    IJavStakeX,
    BaseUpgradable,
    ReentrancyGuardUpgradeable,
    RewardRateConfigurable
{
    using SafeERC20 for IERC20;

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

    /// Info of each pool.
    PoolInfo[] public poolInfo;
    /// Info of each user that stakes want tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    address public rewardsDistributorAddress;

    struct PoolFee {
        uint64 depositFee; //* 1e4
        uint64 withdrawFee; //* 1e4
        uint64 claimFee; //* 1e4
    }

    /// Info of each pool fee.
    PoolFee[] public poolFee;
    uint256 public infinityPassPercent;
    address public infinityPass;
    address public migratorAddress;

    /* ========== EVENTS ========== */

    event SetPoolFee(uint256 _pid, PoolFee _poolFee);

    modifier poolExists(uint256 _pid) {
        require(_pid < poolInfo.length, WrongPool());
        _;
    }

    modifier onlyRewardsDistributor() {
        require(_msgSender() == rewardsDistributorAddress, NotAllowed());
        _;
    }

    modifier onlyMigrator() {
        require(_msgSender() == migratorAddress, NotAllowed());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _rewardPerBlock,
        uint256 _rewardUpdateBlocksInterval,
        address _rewardsDistributorAddress,
        uint256 _infinityPassPercent,
        address _infinityPass,
        address _migratorAddress
    ) external initializer {
        rewardsDistributorAddress = _rewardsDistributorAddress;
        infinityPassPercent = _infinityPassPercent;
        infinityPass = _infinityPass;
        migratorAddress = _migratorAddress;

        __Base_init();
        __ReentrancyGuard_init();
        __RewardRateConfigurable_init(_rewardPerBlock, _rewardUpdateBlocksInterval);

        emit Initialized(_msgSender(), block.number);
    }

    function setRewardsDistributorAddress(address _address) external onlyAdmin {
        rewardsDistributorAddress = _address;

        emit SetRewardsDistributorAddress(_address);
    }

    function setInfinityPassPercent(uint256 _percent) external onlyAdmin {
        infinityPassPercent = _percent;

        emit SetInfinityPassPercent(_percent);
    }

    function setInfinityPass(address _address) external onlyAdmin {
        infinityPass = _address;

        emit SetInfinityPass(_address);
    }

    function setMigratorAddress(address _address) external onlyAdmin {
        migratorAddress = _address;

        emit SetMigratorAddress(_address);
    }

    function setRewardConfiguration(
        uint256 rewardPerBlock,
        uint256 updateBlocksInterval
    ) external onlyAdmin {
        _setRewardConfiguration(rewardPerBlock, updateBlocksInterval);
    }

    /**
     * @notice Function to add new pool
     * @param _baseToken: base pool token
     * @param _rewardToken: rewards pool token
     * @param _minStakeAmount: minimum stake amount for pool
     */
    function addPool(
        address _baseToken,
        address _rewardToken,
        uint256 _lastRewardBlock,
        uint256 _accRewardPerShare,
        uint128 _minStakeAmount,
        PoolFee memory _poolFee
    ) external onlyAdmin {
        poolInfo.push(
            PoolInfo({
                baseToken: IERC20(_baseToken),
                rewardToken: IERC20(_rewardToken),
                totalShares: 0,
                lastRewardBlock: _lastRewardBlock,
                accRewardPerShare: _accRewardPerShare,
                rewardsAmount: 0,
                rewardsPerShare: 0,
                minStakeAmount: _minStakeAmount
            })
        );
        poolFee.push(_poolFee);
        emit SetPoolFee(poolFee.length - 1, _poolFee);
        emit AddPool(_baseToken, _rewardToken, _minStakeAmount);
    }

    function setPoolInfo(
        uint256 pid,
        uint256 lastRewardBlock,
        uint256 accRewardPerShare
    ) external onlyAdmin poolExists(pid) {
        _updatePool(pid, 0);

        PoolInfo storage pool = poolInfo[pid];
        pool.lastRewardBlock = lastRewardBlock;
        pool.accRewardPerShare = accRewardPerShare;

        emit SetPoolInfo(pid, lastRewardBlock, accRewardPerShare);
    }

    function setPoolFee(uint256 pid, PoolFee memory _poolFee) external onlyAdmin poolExists(pid) {
        poolFee[pid] = _poolFee;
        emit SetPoolFee(pid, _poolFee);
    }

    function burnTokens(uint256 _pid, address _holder) external onlyMigrator poolExists(_pid) {
        _updatePool(_pid, 0);
        _claim(_pid, _holder);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_holder];
        uint256 _burnAmount = user.shares;

        user.shares = 0;
        user.blockRewardDebt = 0;
        user.productsRewardDebt = 0;

        pool.totalShares -= _burnAmount;

        _burnToken(address(pool.baseToken), _burnAmount);

        emit BurnTokens(_pid, _holder, _burnAmount);
    }

    function makeMigration(uint256 _pid, uint256 _amount, address _holder) external {}

    /**
     * @notice Function to stake token for selected pool
     * @param _pid: pool id
     * @param _amount: token amount
     */
    function stake(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        PoolInfo memory pool = poolInfo[_pid];
        require(pool.minStakeAmount <= _amount, InvalidAmount());
        require(pool.baseToken.balanceOf(_msgSender()) >= _amount, InvalidAmount());
        _stake(_pid, _msgSender(), _amount);
    }

    /**
     * @notice Function to unstake users asserts from selected pool
     * @param _pid: pool id
     * @param _amount: _amount for unstake
     */
    function unstake(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        _updatePool(_pid, 0);
        _unstake(_pid, _msgSender(), _amount);
    }

    /**
     * @notice Function to claim user rewards for selected pool
     * @param _pid: pool id
     */
    function claim(uint256 _pid) external nonReentrant whenNotPaused {
        _updatePool(_pid, 0);
        _claim(_pid, _msgSender());
    }

    /**
     * @notice Function to claim user rewards from all pools
     */
    function claimAll() external nonReentrant whenNotPaused {
        for (uint256 pid = 0; pid < getPoolLength(); ++pid) {
            _updatePool(pid, 0);
            _claim(pid, _msgSender());
        }
    }

    /**
     * @notice Function to add rewards amount for selected pool
     * @param _pid: pool id
     * @param _amount: rewards amount to be added
     */
    function addRewards(
        uint256 _pid,
        uint256 _amount
    ) external onlyRewardsDistributor nonReentrant {
        _updatePool(_pid, _amount);

        emit AddRewards(_pid, _amount);
    }

    /**
     * @notice Returns pool numbers
     */
    function getPoolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice View function to get pending rewards
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        return _getPendingRewards(_pid, _user);
    }

    function apr(uint256 _pid) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        uint256 totalShares = pool.totalShares > 0 ? pool.totalShares : 1e18;
        return (getRewardPerBlock() * 1051200 * 1e18) / totalShares;
    }

    function userShares(
        uint256 _pid,
        address _user
    ) external view poolExists(_pid) returns (uint256) {
        return userInfo[_pid][_user].shares;
    }

    /**
     * @notice Private function to stake user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _stake(uint256 _pid, address _user, uint256 _amount) private {
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        PoolFee memory fee = poolFee[_pid];
        _updatePool(_pid, 0);

        if (user.shares > 0) {
            _claim(_pid, _user);
        }

        pool.baseToken.safeTransferFrom(_user, address(this), _amount);

        uint256 burnAmount = (_amount * fee.depositFee) / 1e4;
        _burnToken(address(pool.baseToken), burnAmount);
        pool.totalShares += _amount - burnAmount;

        user.shares += _amount - burnAmount;
        user.blockRewardDebt = (user.shares * (pool.accRewardPerShare)) / (1e18);
        user.productsRewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

        emit Stake(_user, _pid, _amount - burnAmount);
    }

    /**
     * @notice Private function to unstake user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _unstake(uint256 _pid, address _user, uint256 _amount) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        PoolFee memory fee = poolFee[_pid];
        require(user.shares >= _amount, InvalidAmount());

        _claim(_pid, _msgSender());
        user.shares -= _amount;
        user.blockRewardDebt = (user.shares * (pool.accRewardPerShare)) / (1e18);
        user.productsRewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

        pool.totalShares -= _amount;

        uint256 burnAmount = (_amount * fee.withdrawFee) / 1e4;

        _burnToken(address(pool.baseToken), burnAmount);
        pool.baseToken.safeTransfer(_user, _amount - burnAmount);

        emit Unstake(_user, _pid, _amount - burnAmount);
    }

    /**
     * @notice Private function to claim user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _claim(uint256 _pid, address _user) private {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        PoolFee memory fee = poolFee[_pid];

        uint256 pending = _getPendingRewards(_pid, _user);
        if (pending > 0) {
            uint256 burnAmount = (pending * fee.claimFee) / 1e4;
            user.totalClaims += pending - burnAmount;

            _burnToken(address(pool.rewardToken), burnAmount);
            pool.rewardToken.safeTransfer(_user, pending - burnAmount);

            user.blockRewardDebt = (user.shares * (pool.accRewardPerShare)) / (1e18);
            user.productsRewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

            emit Claim(address(pool.rewardToken), _user, pending - burnAmount);
        }
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     * @param _pid: Pool id where user has assets
     * @param _rewardsAmount: rewards amount
     */
    function _updatePool(uint256 _pid, uint256 _rewardsAmount) private {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.totalShares == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 _reward = (block.number - pool.lastRewardBlock) * getRewardPerBlock();
        pool.accRewardPerShare = pool.accRewardPerShare + ((_reward * 1e18) / pool.totalShares);
        pool.lastRewardBlock = block.number;
        pool.rewardsAmount += _rewardsAmount;
        pool.rewardsPerShare = (pool.rewardsAmount * 1e18) / pool.totalShares;

        emit UpdatePool(_pid, pool.totalShares, pool.rewardsAmount, pool.rewardsPerShare);
    }

    /**
     * @notice Private function get pending rewards
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _getPendingRewards(uint256 _pid, address _user) private view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];

        if (block.number < pool.lastRewardBlock) {
            return 0;
        }

        uint256 _accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.totalShares != 0) {
            uint256 _multiplier = block.number - pool.lastRewardBlock;
            uint256 _reward = (_multiplier * getRewardPerBlock());
            _accRewardPerShare = _accRewardPerShare + ((_reward * 1e18) / pool.totalShares);
        }

        uint256 blockRewards = ((user.shares * _accRewardPerShare) / 1e18) - user.blockRewardDebt;
        uint256 poolRewards = user.shares * pool.rewardsPerShare;
        uint256 productsRewards = (poolRewards / 1e18) > user.productsRewardDebt
            ? (poolRewards / 1e18) - user.productsRewardDebt
            : 0;

        uint256 nftRewards = IERC721(infinityPass).balanceOf(_user) > 0
            ? ((blockRewards + productsRewards) * infinityPassPercent) / 100
            : 0;

        return blockRewards + productsRewards + nftRewards;
    }

    function _burnToken(address _token, uint256 _amount) private {
        IERC20Extended(_token).burn(_amount);

        emit Burn(_token, _amount);
    }
}
