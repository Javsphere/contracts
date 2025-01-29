// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/leverageX/CollateralUtils.sol";
import "./helpers/RewardRateConfigurable.sol";
import "./abstract/TearmsAndCondUtils.sol";
import "./base/BaseUpgradable.sol";

import "./interfaces/IERC20Extended.sol";
import "./interfaces/IJavFreezer.sol";

contract JavFreezer is
    IJavFreezer,
    TermsAndCondUtils,
    BaseUpgradable,
    ReentrancyGuardUpgradeable,
    RewardRateConfigurable
{
    using SafeERC20 for IERC20;

    PoolInfo[] public poolInfo;
    PoolFee[] public poolFee;
    ProductsRewardsInfo[] public productsRewardsInfo;
    mapping(uint256 => uint256) public lockPeriod;
    mapping(uint256 => uint256) public lockPeriodMultiplier; // * 10e5. i.e 100005 = 1.00005
    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => UserDeposit[])) public userDeposits;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public productsRewardsDebt; //address -> oid -> depositId
    mapping(uint256 => mapping(uint256 => uint256)) public tvl;
    mapping(address => TokenPrecisionInfo) public tokensPrecision;

    address public vestingAddress;
    address public rewardsDistributorAddress;
    address public infinityPass;
    address public migratorAddress;
    address public termsAndConditionsAddress;

    uint256 public infinityPassPercent;
    uint256 public averageBlockTime;

    modifier validLockId(uint256 _lockId) {
        require(lockPeriod[_lockId] != 0 && _lockId < 5, WrongLockPeriod());
        _;
    }

    modifier poolExists(uint256 _pid) {
        require(_pid < poolInfo.length, WrongPool());
        _;
    }

    modifier onlyVesting() {
        require(_msgSender() == vestingAddress, NotAllowed());
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
        address _vestingAddress,
        uint256 _infinityPassPercent,
        address _infinityPass,
        address _migratorAddress,
        address _termsAndConditionsAddress
    ) external initializer {
        vestingAddress = _vestingAddress;
        infinityPassPercent = _infinityPassPercent;
        infinityPass = _infinityPass;
        migratorAddress = _migratorAddress;
        termsAndConditionsAddress = _termsAndConditionsAddress;

        __Base_init();
        __ReentrancyGuard_init();

        emit Initialized(_msgSender(), block.number);
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
        uint256 _accRewardPerShare,
        PoolFee memory _poolFee
    ) external onlyAdmin {
        CollateralUtils.CollateralConfig memory collateralConfig;
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
        poolFee.push(_poolFee);

        collateralConfig = CollateralUtils.getCollateralConfig(_baseToken);
        tokensPrecision[_baseToken] = TokenPrecisionInfo({
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });

        collateralConfig = CollateralUtils.getCollateralConfig(_rewardToken);
        tokensPrecision[_rewardToken] = TokenPrecisionInfo({
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });

        emit SetPoolFee(poolFee.length - 1, _poolFee);
        emit AddPool(_baseToken, _rewardToken, _lastRewardBlock, _accRewardPerShare);
    }

    function setRewardConfiguration(
        uint256 _pid,
        uint256 rewardPerBlock,
        uint256 updateBlocksInterval
    ) external poolExists(_pid) onlyAdmin {
        _setRewardConfiguration(_pid, rewardPerBlock, updateBlocksInterval);
    }

    function setVestingAddress(address _address) external onlyAdmin {
        vestingAddress = _address;

        emit SetVestingAddress(_address);
    }

    function setRewardsDistributorAddress(address _address) external onlyAdmin {
        rewardsDistributorAddress = _address;

        emit SetRewardsDistributorAddress(_address);
    }

    function setAverageBlockTime(uint256 _blockTime) external onlyAdmin {
        averageBlockTime = _blockTime;

        emit SetAverageBlockTime(_blockTime);
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

    function setLockPeriod(uint256 _lockId, uint256 _duration) external onlyAdmin {
        lockPeriod[_lockId] = _duration;

        emit SetLockPeriod(_lockId, _duration);
    }

    function setLockPeriodMultiplier(
        uint256 _lockId,
        uint256 _multiplier
    ) external onlyAdmin validLockId(_lockId) {
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

    function setMigratorAddress(address _address) external onlyAdmin {
        migratorAddress = _address;

        emit SetMigratorAddress(_address);
    }

    function setTermsAndConditionsAddress(
        address _termsAndConditionsAddress
    ) external onlyAdmin nonZeroAddress(_termsAndConditionsAddress) {
        termsAndConditionsAddress = _termsAndConditionsAddress;

        emit SetTermsAndConditionsAddress(_termsAndConditionsAddress);
    }

    function makeMigration(
        uint256 _pid,
        address _holder,
        UserDeposit[] memory _userDeposits
    ) external onlyMigrator poolExists(_pid) {
        UserInfo storage user = userInfo[_holder][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];

        uint256 totalDepositTokens = 0;
        for (uint256 i = 0; i < _userDeposits.length; ++i) {
            totalDepositTokens += _userDeposits[i].depositTokens;
        }

        pool.baseToken.safeTransferFrom(_msgSender(), address(this), totalDepositTokens);

        for (uint256 i = 0; i < _userDeposits.length; ++i) {
            _updatePool(_pid, 0);

            user.totalDepositTokens += _userDeposits[i].depositTokens;
            pool.totalShares += _userDeposits[i].depositTokens;
            tvl[_pid][_userDeposits[i].stakePeriod] += _userDeposits[i].depositTokens;

            uint256 blockRewardDebt = (_userDeposits[i].depositTokens * (pool.accRewardPerShare)) /
                tokensPrecision[address(pool.rewardToken)].precision;
            uint256 productRewardDebt = (_userDeposits[i].depositTokens *
                (productsRewInfo.rewardsPerShare)) /
                tokensPrecision[address(pool.rewardToken)].precision;

            _userDeposits[i].rewardDebt = blockRewardDebt;
            userDeposits[_holder][_pid].push(_userDeposits[i]);
            user.depositId = userDeposits[_holder][_pid].length;
            productsRewardsDebt[_holder][_pid][user.depositId - 1] = productRewardDebt;

            emit Deposit(
                _holder,
                _userDeposits[i].depositTokens,
                _pid,
                _userDeposits[i].stakePeriod,
                _userDeposits[i].depositTimestamp,
                _userDeposits[i].withdrawalTimestamp
            );
        }
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
    )
        external
        nonReentrant
        whenNotPaused
        poolExists(_pid)
        validLockId(_periodId)
        onlyAgreeToTerms(termsAndConditionsAddress)
    {
        PoolInfo memory pool = poolInfo[_pid];
        require(pool.baseToken.balanceOf(_msgSender()) >= _amount, InvalidAmount());
        _deposit(_pid, _amount, _periodId);
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
        require(depositDetails.depositTokens >= _amount, InvalidAmount());
        require(!depositDetails.is_finished, AlreadyFinished());

        _claim(_holder, _pid, _depositId, true);
        depositDetails.depositTokens -= _amount;
        depositDetails.rewardDebt =
            (depositDetails.depositTokens * (pool.accRewardPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        productsRewardsDebt[_holder][_pid][_depositId] =
            (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
            tokensPrecision[address(pool.rewardToken)].precision;

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
        _claim(_msgSender(), _pid, _depositId, false);
    }

    /**
     * @notice Claim All Rewards in one Transaction.
     */
    function claimAllByByLockId(
        uint256 _pid,
        uint256 _lockId
    ) external nonReentrant poolExists(_pid) {
        for (
            uint256 _depositId = 0;
            _depositId < userInfo[_msgSender()][_pid].depositId;
            ++_depositId
        ) {
            UserDeposit memory depositDetails = userDeposits[_msgSender()][_pid][_depositId];
            if (depositDetails.stakePeriod == _lockId) {
                _updatePool(_pid, 0);
                _claim(_msgSender(), _pid, _depositId, false);
            }
        }
    }

    /**
     * @notice Claim All Rewards in one Transaction.
     */
    function claimAll(uint256 _pid) external nonReentrant poolExists(_pid) {
        for (
            uint256 _depositId = 0;
            _depositId < userInfo[_msgSender()][_pid].depositId;
            ++_depositId
        ) {
            _updatePool(_pid, 0);
            _claim(_msgSender(), _pid, _depositId, false);
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
        uint256 totalShares = pool.totalShares > 0
            ? pool.totalShares
            : tokensPrecision[address(pool.rewardToken)].precision;
        return
            (((getRewardPerBlock(_pid) * lockPeriodMultiplier[_lockId] * 15768000) / 1e5) *
                tokensPrecision[address(pool.rewardToken)].precision) / totalShares;
    }

    function userDeposit(
        address _user,
        uint256 _pid,
        uint256 _id
    ) external view returns (UserDeposit memory) {
        return userDeposits[_user][_pid][_id];
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
        (uint256 rewards, ) = _getPendingRewards(_pid, _depositId, _user);
        return rewards;
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
        uint256 _pendingRewards;
        for (uint256 _depositId = 0; _depositId < userInfo[_user][_pid].depositId; ++_depositId) {
            UserDeposit memory depositDetails = userDeposits[_user][_pid][_depositId];
            if (depositDetails.stakePeriod == _lockId) {
                (_pendingRewards, ) = _getPendingRewards(_pid, _depositId, _user);
                rewards += _pendingRewards;
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
        uint256 _pendingRewards;
        for (uint256 _depositId = 0; _depositId < userInfo[_user][_pid].depositId; ++_depositId) {
            (_pendingRewards, ) = _getPendingRewards(_pid, _depositId, _user);
            rewards += _pendingRewards;
        }
        return rewards;
    }

    /**
     * @notice Returns pool numbers
     */
    function getPoolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function userDepositTokens(
        uint256 _pid,
        address _user
    ) external view poolExists(_pid) returns (uint256) {
        return userInfo[_user][_pid].totalDepositTokens;
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
        uint256 _reward = (block.number - pool.lastRewardBlock) * getRewardPerBlock(_pid);
        pool.accRewardPerShare =
            pool.accRewardPerShare +
            ((_reward * tokensPrecision[address(pool.rewardToken)].precision) / pool.totalShares);
        pool.lastRewardBlock = block.number;

        productsRewInfo.rewardsAmount += _rewardsAmount;
        productsRewInfo.rewardsPerShare =
            (productsRewInfo.rewardsAmount * tokensPrecision[address(pool.rewardToken)].precision) /
            pool.totalShares;
    }

    /**
    Should approve allowance before initiating
    accepts depositAmount in WEI
    periodID - id of months array accordingly
    */
    function _deposit(uint256 _pid, uint256 _depositAmount, uint256 _periodId) private {
        UserInfo storage user = userInfo[_msgSender()][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        PoolFee memory fee = poolFee[_pid];
        _updatePool(_pid, 0);

        pool.baseToken.safeTransferFrom(_msgSender(), address(this), _depositAmount);

        uint256 burnAmount = (_depositAmount * fee.depositFee) / 1e4;
        _burnToken(address(pool.baseToken), burnAmount);
        uint256 _userAmount = _depositAmount - burnAmount;

        user.totalDepositTokens += _userAmount;
        pool.totalShares += _userAmount;
        tvl[_pid][_periodId] += _userAmount;

        uint256 blockRewardDebt = (_userAmount * (pool.accRewardPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        uint256 productRewardDebt = (_userAmount * (productsRewInfo.rewardsPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        UserDeposit memory depositDetails = UserDeposit({
            depositTokens: _userAmount,
            stakePeriod: _periodId,
            depositTimestamp: block.timestamp,
            withdrawalTimestamp: block.timestamp + lockPeriod[_periodId],
            is_finished: false,
            rewardsClaimed: 0,
            rewardDebt: blockRewardDebt
        });
        userDeposits[_msgSender()][_pid].push(depositDetails);
        user.depositId = userDeposits[_msgSender()][_pid].length;
        productsRewardsDebt[_msgSender()][_pid][user.depositId - 1] = productRewardDebt;

        emit Deposit(
            _msgSender(),
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
        UserDeposit memory depositDetails = userDeposits[_msgSender()][_pid][_depositId];

        require(depositDetails.withdrawalTimestamp < block.timestamp, PeriodNotEnded());
        require(!depositDetails.is_finished, AlreadyFinished());

        _claim(_msgSender(), _pid, _depositId, true);
        _withdrawDeposit(_msgSender(), _pid, _depositId);
    }

    /*
   Should approve allowance before initiating
   accepts _depositId - is the id of user element.
   */
    function _claim(address _user, uint256 _pid, uint256 _depositId, bool _isWithdraw) private {
        UserInfo storage user = userInfo[_user][_pid];
        UserDeposit storage depositDetails = userDeposits[_user][_pid][_depositId];
        PoolInfo memory pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        PoolFee memory fee = poolFee[_pid];

        (uint256 pending, bool isEnded) = _getPendingRewards(_pid, _depositId, _user);

        if (isEnded && !_isWithdraw) {
            // Withdraw deposit after ended
            _withdrawDeposit(_user, _pid, _depositId);
        }

        if (pending > 0) {
            uint256 burnAmount = (pending * fee.claimFee) / 1e4;
            user.totalClaim += pending - burnAmount;
            depositDetails.rewardsClaimed += pending - burnAmount;
            depositDetails.rewardDebt =
                (depositDetails.depositTokens * (pool.accRewardPerShare)) /
                tokensPrecision[address(pool.rewardToken)].precision;
            productsRewardsDebt[_user][_pid][_depositId] =
                (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
                tokensPrecision[address(pool.rewardToken)].precision;

            _burnToken(address(pool.rewardToken), burnAmount);
            pool.rewardToken.safeTransfer(_user, pending - burnAmount);

            emit ClaimUserReward(_user, pending, _pid, depositDetails.stakePeriod);
        }
    }

    function _getPendingRewards(
        uint256 _pid,
        uint256 _depositId,
        address _user
    ) private view returns (uint256, bool) {
        UserDeposit memory depositDetails = userDeposits[_user][_pid][_depositId];
        PoolInfo memory pool = poolInfo[_pid];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        bool isEnded = false;
        if (
            depositDetails.is_finished ||
            block.timestamp <= depositDetails.depositTimestamp ||
            block.number < pool.lastRewardBlock ||
            pool.accRewardPerShare == 0
        ) {
            return (0, isEnded);
        }

        uint256 effectiveBlock = block.number;
        if (block.timestamp > depositDetails.withdrawalTimestamp) {
            // Stop accumulating rewards after withdrawal timestamp
            effectiveBlock = _getBlockNumberAtTimestamp(depositDetails.withdrawalTimestamp);
            isEnded = true;
        }

        uint256 _accRewardPerShare = pool.accRewardPerShare;

        if (effectiveBlock > pool.lastRewardBlock && pool.totalShares != 0) {
            uint256 _multiplier = effectiveBlock - pool.lastRewardBlock;
            uint256 _reward = (_multiplier * getRewardPerBlock(_pid));
            _accRewardPerShare =
                _accRewardPerShare +
                ((_reward * tokensPrecision[address(pool.rewardToken)].precision) /
                    pool.totalShares);
        }

        uint256 rewards = ((depositDetails.depositTokens * _accRewardPerShare) /
            tokensPrecision[address(pool.rewardToken)].precision) - depositDetails.rewardDebt;
        uint256 depositProductRewards = depositDetails.depositTokens *
            productsRewInfo.rewardsPerShare;
        uint256 productsRewards = depositProductRewards /
            tokensPrecision[address(pool.rewardToken)].precision >
            productsRewardsDebt[_user][_pid][_depositId]
            ? (depositProductRewards / tokensPrecision[address(pool.rewardToken)].precision) -
                productsRewardsDebt[_user][_pid][_depositId]
            : 0;
        uint256 blockRewards = ((rewards * lockPeriodMultiplier[depositDetails.stakePeriod]) / 1e5);

        uint256 nftRewards = IERC721(infinityPass).balanceOf(_user) > 0
            ? ((blockRewards + productsRewards) * infinityPassPercent) / 100
            : 0;

        return (blockRewards + productsRewards + nftRewards, isEnded);
    }

    function _burnToken(address _token, uint256 _amount) private {
        IERC20Extended(_token).burn(_amount);

        emit Burn(_token, _amount);
    }

    function _getBlockNumberAtTimestamp(uint256 timestamp) private view returns (uint256) {
        return block.number - ((block.timestamp - timestamp) / averageBlockTime);
    }

    function _withdrawDeposit(address _user, uint256 _pid, uint256 _depositId) private {
        UserInfo storage user = userInfo[_user][_pid];
        PoolInfo storage pool = poolInfo[_pid];
        UserDeposit storage depositDetails = userDeposits[_user][_pid][_depositId];
        ProductsRewardsInfo memory productsRewInfo = productsRewardsInfo[_pid];
        PoolFee memory fee = poolFee[_pid];

        depositDetails.rewardDebt =
            (depositDetails.depositTokens * (pool.accRewardPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        productsRewardsDebt[_user][_pid][_depositId] =
            (depositDetails.depositTokens * productsRewInfo.rewardsPerShare) /
            tokensPrecision[address(pool.rewardToken)].precision;
        user.totalDepositTokens -= depositDetails.depositTokens;
        pool.totalShares -= depositDetails.depositTokens;
        tvl[_pid][depositDetails.stakePeriod] -= depositDetails.depositTokens;

        uint256 burnAmount = (depositDetails.depositTokens * fee.withdrawFee) / 1e4;

        pool.baseToken.safeTransfer(_user, depositDetails.depositTokens - burnAmount);
        _burnToken(address(pool.baseToken), burnAmount);

        depositDetails.is_finished = true;
        emit Withdraw(
            _user,
            depositDetails.depositTokens - burnAmount,
            _pid,
            depositDetails.stakePeriod
        );
    }
}
