// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./helpers/RewardRateConfigurable.sol";
import "./base/BaseUpgradable.sol";

contract JavStakeX is BaseUpgradable, ReentrancyGuardUpgradeable, RewardRateConfigurable {
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

    /* ========== EVENTS ========== */
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

    modifier poolExists(uint256 _pid) {
        require(_pid < poolInfo.length, "JavStakeX: Unknown pool");
        _;
    }

    modifier onlyRewardsDistributor() {
        require(msg.sender == rewardsDistributorAddress, "JavFreezer: only rewardsDistributor");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _rewardPerBlock,
        uint256 _rewardUpdateBlocksInterval,
        address _rewardsDistributorAddress
    ) external initializer {
        rewardsDistributorAddress = _rewardsDistributorAddress;

        __Base_init();
        __ReentrancyGuard_init();
        __RewardRateConfigurable_init(_rewardPerBlock, _rewardUpdateBlocksInterval);

        emit Initialized(msg.sender, block.number);
    }

    function setRewardsDistributorAddress(address _address) external onlyAdmin {
        rewardsDistributorAddress = _address;

        emit SetRewardsDistributorAddress(_address);
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
        uint128 _minStakeAmount
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

    /**
     * @notice Function to stake token for selected pool
     * @param _pid: pool id
     * @param _amount: token amount
     */
    function stake(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        PoolInfo memory pool = poolInfo[_pid];
        require(pool.minStakeAmount <= _amount, "JavStakeX: invalid amount for stake");
        require(
            pool.baseToken.balanceOf(msg.sender) >= _amount,
            "JavStakeX: invalid balance for stake"
        );
        _stake(_pid, msg.sender, _amount);
    }

    /**
     * @notice Function to unstake users asserts from selected pool
     * @param _pid: pool id
     * @param _amount: _amount for unstake
     */
    function unstake(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        _updatePool(_pid, 0);
        _unstake(_pid, msg.sender, _amount);
    }

    /**
     * @notice Function to claim user rewards for selected pool
     * @param _pid: pool id
     */
    function claim(uint256 _pid) external nonReentrant whenNotPaused {
        _updatePool(_pid, 0);
        _claim(_pid, msg.sender);
    }

    /**
     * @notice Function to claim user rewards from all pools
     */
    function claimAll() external nonReentrant whenNotPaused {
        for (uint256 pid = 0; pid < getPoolLength(); ++pid) {
            _updatePool(pid, 0);
            _claim(pid, msg.sender);
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
        return ((getRewardPerBlock() * 1051200 + pool.rewardsAmount) * 1e18) / totalShares;
    }

    /**
     * @notice Private function to stake user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _stake(uint256 _pid, address _user, uint256 _amount) private {
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        _updatePool(_pid, 0);

        if (user.shares > 0) {
            _claim(_pid, _user);
        }

        pool.baseToken.safeTransferFrom(_user, address(this), _amount);

        pool.totalShares += _amount;

        user.shares += _amount;
        user.blockRewardDebt = (user.shares * (pool.accRewardPerShare)) / (1e18);
        user.productsRewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

        emit Stake(_user, _pid, _amount);
    }

    /**
     * @notice Private function to unstake user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _unstake(uint256 _pid, address _user, uint256 _amount) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.shares >= _amount, "JavStakeX: invalid amount for unstake");

        _claim(_pid, msg.sender);
        user.shares -= _amount;
        user.blockRewardDebt = (user.shares * (pool.accRewardPerShare)) / (1e18);
        user.productsRewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

        pool.totalShares -= _amount;

        pool.baseToken.safeTransfer(_user, _amount);

        emit Unstake(_user, _pid, _amount);
    }

    /**
     * @notice Private function to claim user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _claim(uint256 _pid, address _user) private {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 pending = _getPendingRewards(_pid, _user);
        if (pending > 0) {
            user.totalClaims += pending;
            pool.rewardToken.safeTransfer(_user, pending);

            user.blockRewardDebt = (user.shares * (pool.accRewardPerShare)) / (1e18);
            user.productsRewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

            emit Claim(address(pool.rewardToken), _user, pending);
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
        uint256 productsRewards = ((user.shares * pool.rewardsPerShare) / 1e18) >
            user.productsRewardDebt
            ? ((user.shares * pool.rewardsPerShare) / 1e18) - user.productsRewardDebt
            : 0;

        return blockRewards + productsRewards;
    }
}
