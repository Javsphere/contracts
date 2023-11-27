// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./base/BaseUpgradable.sol";

contract JavStakeX is ReentrancyGuardUpgradeable, AccessControlUpgradeable, BaseUpgradable {
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
        uint256 rewardsAmount;
        uint128 rewardsPerShare;
        uint128 minStakeAmount;
    }

    struct UserInfo {
        uint256 shares;
        uint256 rewardDebt;
        uint256 totalClaims;
    }

    /// Info of each pool.
    PoolInfo[] public poolInfo;
    /// Info of each user that stakes want tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

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
    event Stake(address indexed _address, uint256 indexed _pid, uint256 _amount);
    event Unstake(address indexed _address, uint256 _pid, uint256 _amount);
    event Claim(address indexed _token, address indexed _user, uint256 _amount);
    event UpdateRewards(address indexed _address);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        _grantRole(0x00, msg.sender);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Base_init();
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
        uint128 _minStakeAmount
    ) external onlyAdmin {
        poolInfo.push(
            PoolInfo({
                baseToken: IERC20(_baseToken),
                rewardToken: IERC20(_rewardToken),
                totalShares: 0,
                rewardsAmount: 0,
                rewardsPerShare: 0,
                minStakeAmount: _minStakeAmount
            })
        );

        emit AddPool(_baseToken, _rewardToken, _minStakeAmount);
    }

    /**
     * @notice Function to stake token for selected pool
     * @param _pid: pool id
     * @param _amount: token amount
     */
    function stake(uint256 _pid, uint256 _amount) external nonReentrant {
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
     */
    function unstake(uint256 _pid) external nonReentrant {
        _unstake(_pid, msg.sender);
    }

    /**
     * @notice Function to claim user rewards for selected pool
     * @param _pid: pool id
     */
    function claim(uint256 _pid) external nonReentrant {
        _claim(_pid, msg.sender);
    }

    /**
     * @notice Function to claim user rewards from all pools
     */
    function claimAll() external nonReentrant {
        for (uint256 pid = 0; pid < getPoolLength(); ++pid) {
            _claim(pid, msg.sender);
        }
    }

    /**
     * @notice Function to update rewards amount for selected pool
     * @param _pid: pool id
     * @param _amount: rewards amount to be added
     */
    function updateRewards(uint256 _pid, uint256 _amount) external onlyRole("0x02") nonReentrant {
        _updatePool(_pid, 0, _amount, true);
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

    /**
     * @notice Private function to stake user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _stake(uint256 _pid, address _user, uint256 _amount) private {
        UserInfo storage user = userInfo[_pid][_user];

        if (user.shares > 0) {
            _claim(_pid, _user);
        }
        PoolInfo memory pool = poolInfo[_pid];

        pool.baseToken.safeTransferFrom(_user, address(this), _amount);
        _updatePool(_pid, _amount, 0, true);
        pool = poolInfo[_pid];

        user.shares += _amount;

        user.rewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);

        emit Stake(_user, _pid, _amount);
    }

    /**
     * @notice Private function to unstake user asserts
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function _unstake(uint256 _pid, address _user) private {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 _amount = user.shares;
        require(_amount > 0, "JavStakeX: user amount is 0");

        _claim(_pid, msg.sender);
        user.shares = 0;
        user.rewardDebt = 0;
        pool.baseToken.safeTransfer(_user, _amount);

        _updatePool(_pid, _amount, 0, false);

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
            emit Claim(address(pool.rewardToken), _user, pending);
        }
        user.rewardDebt = (user.shares * (pool.rewardsPerShare)) / (1e18);
    }

    /**
     * @notice Private function to update pool
     * @param _pid: Pool id where user has assets
     * @param _shares: shares amount
     * @param _rewardsAmount: rewards amount
     * @param isDeposit: bool flag - deposit or no
     */
    function _updatePool(
        uint256 _pid,
        uint256 _shares,
        uint256 _rewardsAmount,
        bool isDeposit
    ) private {
        PoolInfo storage pool = poolInfo[_pid];
        if (isDeposit) {
            pool.totalShares += _shares;
        } else {
            pool.totalShares -= _shares;
        }
        pool.rewardsAmount += _rewardsAmount;
        pool.rewardsPerShare = pool.totalShares > 0
            ? uint128((pool.rewardsAmount * 1e18) / pool.totalShares)
            : 0;

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
        return
            (user.shares * pool.rewardsPerShare) / 1e18 > user.rewardDebt
                ? (user.shares * pool.rewardsPerShare) / 1e18 - user.rewardDebt
                : 0;
    }
}
