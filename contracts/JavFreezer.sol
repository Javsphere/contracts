// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./helpers/RewardRateConfigurable.sol";
import "./base/BaseUpgradable.sol";
import "./interfaces/IJavFreezer.sol";
import "./interfaces/IERC20Extended.sol";

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
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public productsRewardsDebt; //address -> oid -> depositId

    address public rewardsDistributorAddress;

    struct ProductsRewardsInfo {
        uint256 rewardsAmount;
        uint256 rewardsPerShare;
    }
    ProductsRewardsInfo[] public productsRewardsInfo;
    mapping(uint256 => mapping(uint256 => uint256)) public tvl;

    struct PoolFee {
        uint64 depositFee; //* 1e4
        uint64 withdrawFee; //* 1e4
        uint64 claimFee; //* 1e4
    }

    /// Info of each pool fee.
    PoolFee[] public poolFee;
    uint256 public infinityPassPercent;
    address public infinityPass;

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
    event SetPoolFee(uint256 _pid, PoolFee _poolFee);
    event Burn(address _token, uint256 _amount);
    event SetInfinityPassPercent(uint256 indexed _percent);
    event SetInfinityPass(address indexed _address);

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
        address _vestingAddress
    ) external initializer {
        vestingAddress = _vestingAddress;

        __Base_init();
        __ReentrancyGuard_init();
        __RewardRateConfigurable_init(_rewardPerBlock, _rewardUpdateBlocksInterval);

        emit Initialized(msg.sender, block.number);
    }

    function setTvl(uint256 _pid, uint256 _lockId, uint256 _tvl) external onlyAdmin {
        require(_lockId == 5 || _lockId == 6, "JavFreezer: invalid lock period");
        tvl[_pid][_lockId] = _tvl;
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
        productsRewardsInfo.push(ProductsRewardsInfo({rewardsAmount: 0, rewardsPerShare: 0}));

        emit AddPool(_baseToken, _rewardToken, _lastRewardBlock, _accRewardPerShare);
    }

    function addPoolRewardsInfo() external onlyAdmin {
        require(
            poolInfo.length > productsRewardsInfo.length,
            "JavFreezer: rewards pool already exists"
        );
        productsRewardsInfo.push(ProductsRewardsInfo({rewardsAmount: 0, rewardsPerShare: 0}));
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

    function setRewardsDistributorAddress(address _address) external onlyAdmin {
        rewardsDistributorAddress = _address;

        emit SetRewardsDistributorAddress(_address);
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

    function addPoolFee(PoolFee memory _poolFee) external onlyAdmin {
        poolFee.push(_poolFee);
        emit SetPoolFee(poolFee.length - 1, _poolFee);
    }

    function setPoolFee(uint256 pid, PoolFee memory _poolFee) external onlyAdmin poolExists(pid) {
        poolFee[pid] = _poolFee;
        emit SetPoolFee(pid, _poolFee);
    }

    function setLockPeriod(uint256 _lockId, uint256 _duration) external onlyAdmin {
        lockPeriod[_lockId] = _duration;

        emit SetLockPeriod(_lockId, _duration);
    }

    function setLockPeriodMultiplier(uint256 _lockId, uint256 _multiplier) external onlyAdmin {
        lockPeriodMultiplier[_lockId] = _multiplier;

        emit SetLockPeriodMultiplier(_lockId, _multiplier);
    }

    function setInfinityPassPercent(uint256 _percent) external onlyAdmin {
        infinityPassPercent = _percent;

        emit SetInfinityPassPercent(_percent);
    }

    function setInfinityPass(address _address) external onlyAdmin {
        infinityPass = _address;

        emit SetInfinityPass(_address);
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
        _updatePool(_pid, 0);

        user.totalDepositTokens += _amount;
        pool.totalShares += _amount;
        tvl[_pid][_lockId] += _amount;

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

        emit Deposit(_holder, _amount, _pid, _lockId, _depositTimestamp, _withdrawalTimestamp);
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
        _updatePool(_pid, 0);
        UserInfo storage user = userInfo[_holder][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        UserDeposit storage depositDetails = userDeposits[_holder][_pid][_depositId];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        require(depositDetails.depositTokens >= _amount, "JavFreezer: invalid withdraw amount");
        require(!depositDetails.is_finished, "JavFreezer: already withdrawn");

        _claim(_holder, _pid, _depositId);
        depositDetails.depositTokens -= _amount;
        depositDetails.rewardDebt =
            (depositDetails.depositTokens * (pool.accRewardPerShare)) /
            (1e18);
        productsRewardsDebt[_holder][_pid][_depositId] =
            (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
            (1e18);

        user.totalDepositTokens -= _amount;
        pool.totalShares -= _amount;
        tvl[_pid][depositDetails.stakePeriod] -= _amount;

        pool.baseToken.safeTransfer(_holder, _amount);

        if (depositDetails.depositTokens == 0) {
            depositDetails.is_finished = true;
        }
        emit Withdraw(_holder, _amount, _pid, depositDetails.stakePeriod);
    }

    /**
     * @notice withdraw one claim
     * @param _pid: pool id.
     * @param _depositId: is the id of user element.
     */
    function withdraw(uint256 _pid, uint256 _depositId) external nonReentrant poolExists(_pid) {
        _updatePool(_pid, 0);
        _withdraw(_pid, _depositId);
    }

    /**
     * @notice Claim rewards you gained over period
     * @param _pid: pool id.
     * @param _depositId: is the id of user element.
     */
    function claim(uint256 _pid, uint256 _depositId) external nonReentrant poolExists(_pid) {
        _updatePool(_pid, 0);
        _claim(msg.sender, _pid, _depositId);
    }

    /**
     * @notice Claim All Rewards in one Transaction.
     */
    function claimAllByByLockId(
        uint256 _pid,
        uint256 _lockId
    ) external nonReentrant poolExists(_pid) validLockId(_lockId) {
        for (
            uint256 _depositId = 0;
            _depositId < userInfo[msg.sender][_pid].depositId;
            ++_depositId
        ) {
            UserDeposit memory depositDetails = userDeposits[msg.sender][_pid][_depositId];
            if (depositDetails.stakePeriod == _lockId) {
                _updatePool(_pid, 0);
                _claim(msg.sender, _pid, _depositId);
            }
        }
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
            _updatePool(_pid, 0);
            _claim(msg.sender, _pid, _depositId);
        }
    }

    function addRewards(
        uint256 _pid,
        uint256 _amount
    ) external onlyRewardsDistributor nonReentrant {
        _updatePool(_pid, _amount);

        emit AddRewards(_pid, _amount);
    }

    function getUserLastDepositId(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user][_pid];

        return user.depositId - 1;
    }

    function apr(uint256 _pid, uint256 _lockId) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        uint256 totalShares = pool.totalShares > 0 ? pool.totalShares : 1e18;
        return
            (((getRewardPerBlock() * lockPeriodMultiplier[_lockId] * 1051200) / 1e5) * 1e18) /
            totalShares;
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
     * @notice View function to see pending reward on frontend.
     * @param _pid: Staking pool id
     * @param _lockId: lock period id
     * @param _user: User address
     */
    function pendingRewardByLockId(
        uint256 _pid,
        uint256 _lockId,
        address _user
    ) external view returns (uint256) {
        uint256 rewards;
        for (uint256 _depositId = 0; _depositId < userInfo[_user][_pid].depositId; ++_depositId) {
            UserDeposit memory depositDetails = userDeposits[_user][_pid][_depositId];
            if (depositDetails.stakePeriod == _lockId) {
                rewards += _getPendingRewards(_pid, _depositId, _user);
            }
        }
        return rewards;
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
     * @param _pid: Pool id where user has assets
     * @param _rewardsAmount: rewards amount
     */
    function _updatePool(uint256 _pid, uint256 _rewardsAmount) private {
        PoolInfo storage pool = poolInfo[_pid];
        ProductsRewardsInfo storage productsRewInfo = productsRewardsInfo[_pid];

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

        productsRewInfo.rewardsAmount += _rewardsAmount;
        productsRewInfo.rewardsPerShare = (productsRewInfo.rewardsAmount * 1e18) / pool.totalShares;
    }

    /**
    Should approve allowance before initiating
    accepts depositAmount in WEI
    periodID - id of months array accordingly
    */
    function _deposit(uint256 _pid, uint256 _depositAmount, uint256 _periodId) private {
        UserInfo storage user = userInfo[msg.sender][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        PoolFee memory fee = poolFee[_pid];
        _updatePool(_pid, 0);

        pool.baseToken.safeTransferFrom(msg.sender, address(this), _depositAmount);

        uint256 burnAmount = (_depositAmount * fee.depositFee) / 1e4;
        _burnToken(address(pool.baseToken), burnAmount);
        uint256 _userAmount = _depositAmount - burnAmount;

        user.totalDepositTokens += _userAmount;
        pool.totalShares += _userAmount;
        tvl[_pid][_periodId] += _userAmount;

        uint256 blockRewardDebt = (_userAmount * (pool.accRewardPerShare)) / (1e18);
        uint256 productRewardDebt = (_userAmount * (productsRewInfo.rewardsPerShare)) / (1e18);
        UserDeposit memory depositDetails = UserDeposit({
            depositTokens: _userAmount,
            stakePeriod: _periodId,
            depositTimestamp: block.timestamp,
            withdrawalTimestamp: block.timestamp + lockPeriod[_periodId],
            is_finished: false,
            rewardsClaimed: 0,
            rewardDebt: blockRewardDebt
        });
        userDeposits[msg.sender][_pid].push(depositDetails);
        user.depositId = userDeposits[msg.sender][_pid].length;
        productsRewardsDebt[msg.sender][_pid][user.depositId - 1] = productRewardDebt;

        emit Deposit(
            msg.sender,
            _userAmount,
            _pid,
            _periodId,
            depositDetails.depositTimestamp,
            depositDetails.withdrawalTimestamp
        );
    }

    /**
    Should approve allowance before initiating
    accepts _depositId - is the id of user element.
    */
    function _withdraw(uint256 _pid, uint256 _depositId) private {
        UserInfo storage user = userInfo[msg.sender][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        UserDeposit storage depositDetails = userDeposits[msg.sender][_pid][_depositId];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        PoolFee memory fee = poolFee[_pid];
        require(
            depositDetails.withdrawalTimestamp < block.timestamp,
            "JavFreezer: lock period hasn't ended."
        );
        require(!depositDetails.is_finished, "JavFreezer: already withdrawn");

        _claim(msg.sender, _pid, _depositId);
        depositDetails.rewardDebt =
            (depositDetails.depositTokens * (pool.accRewardPerShare)) /
            (1e18);
        productsRewardsDebt[msg.sender][_pid][_depositId] =
            (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
            (1e18);
        user.totalDepositTokens -= depositDetails.depositTokens;
        pool.totalShares -= depositDetails.depositTokens;
        tvl[_pid][depositDetails.stakePeriod] -= depositDetails.depositTokens;

        uint256 burnAmount = (depositDetails.depositTokens * fee.withdrawFee) / 1e4;

        pool.baseToken.safeTransfer(msg.sender, depositDetails.depositTokens - burnAmount);
        _burnToken(address(pool.baseToken), burnAmount);

        depositDetails.is_finished = true;
        emit Withdraw(
            msg.sender,
            depositDetails.depositTokens - burnAmount,
            _pid,
            depositDetails.stakePeriod
        );
    }

    /*
   Should approve allowance before initiating
   accepts _depositId - is the id of user element.
   */
    function _claim(address _user, uint256 _pid, uint256 _depositId) private {
        UserInfo storage user = userInfo[_user][_pid];
        UserDeposit storage depositDetails = userDeposits[_user][_pid][_depositId];
        PoolInfo memory pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        PoolFee memory fee = poolFee[_pid];

        uint256 pending = _getPendingRewards(_pid, _depositId, _user);

        if (pending > 0) {
            uint256 burnAmount = (pending * fee.claimFee) / 1e4;
            user.totalClaim += pending - burnAmount;
            depositDetails.rewardsClaimed += pending - burnAmount;
            depositDetails.rewardDebt =
                (depositDetails.depositTokens * (pool.accRewardPerShare)) /
                (1e18);
            productsRewardsDebt[_user][_pid][_depositId] =
                (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
                (1e18);

            _burnToken(address(pool.rewardToken), burnAmount);
            pool.rewardToken.safeTransfer(_user, pending - burnAmount);

            emit ClaimUserReward(_user, pending, _pid, depositDetails.stakePeriod);
        }
    }

    function _getPendingRewards(
        uint256 _pid,
        uint256 _depositId,
        address _user
    ) private view returns (uint256) {
        UserDeposit memory depositDetails = userDeposits[_user][_pid][_depositId];
        PoolInfo memory pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
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
        uint256 productsRewards = (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
            1e18 >
            productsRewardsDebt[_user][_pid][_depositId]
            ? ((depositDetails.depositTokens * productsRewInfo.rewardsPerShare) / 1e18) -
                productsRewardsDebt[_user][_pid][_depositId]
            : 0;
        uint256 blockRewards = ((rewards * lockPeriodMultiplier[depositDetails.stakePeriod]) / 1e5);

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
