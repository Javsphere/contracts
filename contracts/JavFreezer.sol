// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./helpers/RewardRateConfigurable.sol";
import "./base/BaseUpgradable.sol";
import "./interfaces/IJavFreezer.sol";

contract JavFreezer is
    IJavFreezer,
    BaseUpgradable,
    ReentrancyGuardUpgradeable,
    RewardRateConfigurable
{
    using SafeERC20 for IERC20;

    /**
     * @notice Info of each user
     * One Address can have many Deposits with different periods. Unlimited Amount.
     * Total Deposit Tokens = Total amount of user active stake in all.
     * depositId = incremental ID of deposits, eg. if user has 3 staking then this value will be 2;
     * totalClaim = Total amount of tokens user claim.
     */
    struct UserInfo {
        uint256 totalDepositTokens;
        uint256 depositId;
        uint256 totalClaim;
    }

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
    /**
     * @notice Info of Pool
     * @param lastRewardBlock: Last block number that reward distribution occurs
     * @param accUTacoPerShare: Accumulated rewardPool per share, times 1e18
     */
    struct PoolInfo {
        IERC20 baseToken;
        IERC20 rewardToken;
        uint256 totalShares;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
    }

    address public vestingAddress;

    PoolInfo[] public poolInfo;
    mapping(uint256 => uint256) public lockPeriod;
    mapping(uint256 => uint256) public lockPeriodMultiplier; // * 10e5. i.e 100005 = 1.00005
    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => UserDeposit[])) public userDeposits;
    /* ========== EVENTS ========== */
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
    event ClaimUserReward(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount, uint256 indexed period);
    event Withdraw(address indexed user, uint256 amount, uint256 indexed period);

    modifier validLockId(uint256 _lockId) {
        require(lockPeriod[_lockId] != 0 && _lockId < 5, "JavFreezer: invalid lock period");
        _;
    }

    modifier poolExists(uint256 _pid) {
        require(_pid < poolInfo.length, "JavFreezer: Unknown pool");
        _;
    }

    modifier onlyVesting() {
        require(msg.sender == vestingAddress, "JavFreezer: only vesting");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _rewardPerBlock,
        uint256 _rewardUpdateBlocksInterval,
        address _vestingAddress
    ) external initializer {
        vestingAddress = _vestingAddress;

        __Base_init();
        __ReentrancyGuard_init();
        __RewardRateConfigurable_init(_rewardPerBlock, _rewardUpdateBlocksInterval);

        emit Initialized(msg.sender, block.number);
    }

    /**
     * @notice Function to add new pool
     * @param _baseToken: base pool token
     * @param _rewardToken: rewards pool token
     * @param _lastRewardBlock: last reward block
     * @param _accRewardPerShare: accRewardPerShare
     */
    function addPool(
        address _baseToken,
        address _rewardToken,
        uint256 _lastRewardBlock,
        uint256 _accRewardPerShare
    ) external onlyAdmin {
        poolInfo.push(
            PoolInfo({
                baseToken: IERC20(_baseToken),
                rewardToken: IERC20(_rewardToken),
                totalShares: 0,
                lastRewardBlock: _lastRewardBlock,
                accRewardPerShare: _accRewardPerShare
            })
        );

        emit AddPool(_baseToken, _rewardToken, _lastRewardBlock, _accRewardPerShare);
    }

    function setRewardConfiguration(
        uint256 rewardPerBlock,
        uint256 updateBlocksInterval
    ) external onlyAdmin {
        _setRewardConfiguration(rewardPerBlock, updateBlocksInterval);
    }

    function setVestingAddress(address _address) external onlyAdmin {
        vestingAddress = _address;

        emit SetVestingAddress(_address);
    }

    function setPoolInfo(
        uint256 pid,
        uint256 lastRewardBlock,
        uint256 accRewardPerShare
    ) external onlyAdmin poolExists(pid) {
        updatePool(pid);

        PoolInfo storage pool = poolInfo[pid];
        pool.lastRewardBlock = lastRewardBlock;
        pool.accRewardPerShare = accRewardPerShare;

        emit SetPoolInfo(pid, lastRewardBlock, accRewardPerShare);
    }

    function setLockPeriod(uint256 _lockId, uint256 _duration) external onlyAdmin {
        lockPeriod[_lockId] = _duration;

        emit SetLockPeriod(_lockId, _duration);
    }

    function setLockPeriodMultiplier(uint256 _lockId, uint256 _multiplier) external onlyAdmin {
        lockPeriodMultiplier[_lockId] = _multiplier;

        emit SetLockPeriodMultiplier(_lockId, _multiplier);
    }

    /**
     * @notice Deposit in given pool
     * @param _periodId: stake period
     * @param _amount: Amount of want token that user wants to deposit
     */
    function deposit(
        uint256 _pid,
        uint256 _periodId,
        uint256 _amount
    ) external nonReentrant whenNotPaused poolExists(_pid) validLockId(_periodId) {
        PoolInfo memory pool = poolInfo[_pid];
        require(
            pool.baseToken.balanceOf(msg.sender) >= _amount,
            "JavFreezer: invalid balance for deposit"
        );
        _deposit(_pid, _amount, _periodId);
    }

    /**
     * @notice Deposit in given pool from vesting
     * @param _holder: holder address
     * @param _pid: pool id
     * @param _amount: Amount of want token that user wants to deposit
     */
    function depositVesting(
        address _holder,
        uint256 _pid,
        uint256 _amount,
        uint256 _depositTimestamp,
        uint256 _withdrawalTimestamp,
        uint256 _lockId
    ) external nonReentrant whenNotPaused poolExists(_pid) onlyVesting {
        UserInfo storage user = userInfo[_holder][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        updatePool(_pid);

        user.totalDepositTokens += _amount;
        pool.totalShares += _amount;

        uint256 rewardDebt = (_amount * (pool.accRewardPerShare)) / (1e18);
        UserDeposit memory depositDetails = UserDeposit({
            depositTokens: _amount,
            stakePeriod: _lockId,
            depositTimestamp: _depositTimestamp,
            withdrawalTimestamp: _withdrawalTimestamp,
            is_finished: false,
            rewardsClaimed: 0,
            rewardDebt: rewardDebt
        });
        userDeposits[_holder][_pid].push(depositDetails);
        user.depositId = userDeposits[_holder][_pid].length;

        emit Deposit(_holder, _amount, 0);
    }

    /**
     * @notice Withdraw amount from freeze schedule
     * @param _holder: holder address
     * @param _pid: pool id
     * @param _depositId: deposit id
     * @param _amount: Amount of want token that user wants to deposit
     */
    function withdrawVesting(
        address _holder,
        uint256 _pid,
        uint256 _depositId,
        uint256 _amount
    ) external nonReentrant whenNotPaused poolExists(_pid) onlyVesting {
        updatePool(_pid);
        UserInfo storage user = userInfo[_holder][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        UserDeposit storage depositDetails = userDeposits[_holder][_pid][_depositId];
        require(depositDetails.depositTokens >= _amount, "JavFreezer: invalid withdraw amount");
        require(!depositDetails.is_finished, "JavFreezer: already withdrawn");

        _claim(_holder, _pid, _depositId);
        depositDetails.depositTokens -= _amount;
        depositDetails.rewardDebt =
            (depositDetails.depositTokens * (pool.accRewardPerShare)) /
            (1e18);

        user.totalDepositTokens -= _amount;
        pool.totalShares -= _amount;

        pool.baseToken.safeTransfer(_holder, _amount);

        if (depositDetails.depositTokens == 0) {
            depositDetails.is_finished = true;
        }
        emit Withdraw(_holder, _amount, depositDetails.stakePeriod);
    }

    /**
     * @notice withdraw one claim
     * @param _pid: pool id.
     * @param _depositId: is the id of user element.
     */
    function withdraw(uint256 _pid, uint256 _depositId) external nonReentrant poolExists(_pid) {
        updatePool(_pid);
        _withdraw(_pid, _depositId);
    }

    /**
     * @notice Claim rewards you gained over period
     * @param _pid: pool id.
     * @param _depositId: is the id of user element.
     */
    function claim(uint256 _pid, uint256 _depositId) external nonReentrant poolExists(_pid) {
        updatePool(_pid);
        _claim(msg.sender, _pid, _depositId);
    }

    /**
     * @notice Claim All Rewards in one Transaction.
     */
    function claimAll(uint256 _pid) external nonReentrant poolExists(_pid) {
        for (
            uint256 _depositId = 0;
            _depositId < userInfo[msg.sender][_pid].depositId;
            ++_depositId
        ) {
            updatePool(_pid);
            _claim(msg.sender, _pid, _depositId);
        }
    }

    function getUserLastDepositId(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user][_pid];

        return user.depositId - 1;
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _depositId: Staking pool id
     * @param _user: User address
     */
    function pendingReward(
        uint256 _pid,
        uint256 _depositId,
        address _user
    ) external view returns (uint256) {
        return _getPendingRewards(_pid, _depositId, _user);
    }

    /**
     * @notice View function to see all pending rewards
     * @param _user: User address
     */
    function pendingRewardTotal(uint256 _pid, address _user) external view returns (uint256) {
        uint256 rewards;
        for (uint256 _depositId = 0; _depositId < userInfo[_user][_pid].depositId; ++_depositId) {
            rewards += _getPendingRewards(_pid, _depositId, _user);
        }
        return rewards;
    }

    /**
     * @notice Returns pool numbers
     */
    function getPoolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function updatePool(uint256 _pid) public {
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

        // Update rewardPerBlock right AFTER pool update
        _updateRewardPerBlock();
    }

    /**
    Should approve allowance before initiating
    accepts depositAmount in WEI
    periodID - id of months array accordingly
    */
    function _deposit(uint256 _pid, uint256 _depositAmount, uint256 _periodId) private {
        UserInfo storage user = userInfo[msg.sender][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        updatePool(_pid);

        pool.baseToken.safeTransferFrom(msg.sender, address(this), _depositAmount);

        user.totalDepositTokens += _depositAmount;
        pool.totalShares += _depositAmount;

        uint256 rewardDebt = (_depositAmount * (pool.accRewardPerShare)) / (1e18);
        UserDeposit memory depositDetails = UserDeposit({
            depositTokens: _depositAmount,
            stakePeriod: _periodId,
            depositTimestamp: block.timestamp,
            withdrawalTimestamp: block.timestamp + lockPeriod[_periodId],
            is_finished: false,
            rewardsClaimed: 0,
            rewardDebt: rewardDebt
        });
        userDeposits[msg.sender][_pid].push(depositDetails);
        user.depositId = userDeposits[msg.sender][_pid].length;

        emit Deposit(msg.sender, _depositAmount, _periodId);
    }

    /**
    Should approve allowance before initiating
    accepts _depositId - is the id of user element.
    */
    function _withdraw(uint256 _pid, uint256 _depositId) private {
        UserInfo storage user = userInfo[msg.sender][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        UserDeposit storage depositDetails = userDeposits[msg.sender][_pid][_depositId];
        require(
            depositDetails.withdrawalTimestamp < block.timestamp,
            "JavFreezer: lock period hasn't ended."
        );
        require(!depositDetails.is_finished, "JavFreezer: already withdrawn");

        _claim(msg.sender, _pid, _depositId);
        depositDetails.rewardDebt =
            (depositDetails.depositTokens * (pool.accRewardPerShare)) /
            (1e18);

        user.totalDepositTokens -= depositDetails.depositTokens;
        pool.totalShares -= depositDetails.depositTokens;

        pool.baseToken.safeTransfer(msg.sender, depositDetails.depositTokens);

        depositDetails.is_finished = true;
        emit Withdraw(msg.sender, depositDetails.depositTokens, depositDetails.stakePeriod);
    }

    /*
   Should approve allowance before initiating
   accepts _depositId - is the id of user element.
   */
    function _claim(address _user, uint256 _pid, uint256 _depositId) private {
        UserInfo storage user = userInfo[_user][_pid];
        UserDeposit storage depositDetails = userDeposits[_user][_pid][_depositId];
        PoolInfo memory pool = poolInfo[_pid];

        uint256 pending = _getPendingRewards(_pid, _depositId, _user);

        if (pending > 0) {
            user.totalClaim += pending;
            depositDetails.rewardsClaimed += pending;
            depositDetails.rewardDebt =
                (depositDetails.depositTokens * (pool.accRewardPerShare)) /
                (1e18);

            pool.rewardToken.safeTransfer(_user, pending);

            emit ClaimUserReward(_user, pending);
        }
    }

    function _getPendingRewards(
        uint256 _pid,
        uint256 _depositId,
        address _user
    ) private view returns (uint256) {
        UserDeposit memory depositDetails = userDeposits[_user][_pid][_depositId];
        PoolInfo memory pool = poolInfo[_pid];
        if (
            depositDetails.is_finished ||
            block.timestamp <= depositDetails.depositTimestamp ||
            block.number < pool.lastRewardBlock
        ) {
            return 0;
        }

        uint256 _accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.totalShares != 0) {
            uint256 _multiplier = block.number - pool.lastRewardBlock;
            uint256 _reward = (_multiplier * getRewardPerBlock());
            _accRewardPerShare = _accRewardPerShare + ((_reward * 1e18) / pool.totalShares);
        }

        uint256 rewards = ((depositDetails.depositTokens * _accRewardPerShare) / 1e18) -
            depositDetails.rewardDebt;
        return (rewards * lockPeriodMultiplier[depositDetails.stakePeriod]) / 1e5;
    }
}
