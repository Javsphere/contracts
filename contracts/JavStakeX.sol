// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./libraries/leverageX/CollateralUtils.sol";
import "./helpers/RewardRateConfigurable.sol";
import "./abstract/TearmsAndCondUtils.sol";

import "./interfaces/IERC20Extended.sol";
import "./base/BaseUpgradable.sol";
import "./interfaces/IJavStakeX.sol";

contract JavStakeX is
    IJavStakeX,
    TermsAndCondUtils,
    BaseUpgradable,
    ReentrancyGuardUpgradeable,
    RewardRateConfigurable
{
    using SafeERC20 for IERC20;

    /// Info of each pool.
    PoolInfo[] public poolInfo;
    PoolFee[] public poolFee;
    /// Info of each user that stakes want tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => TokenPrecisionInfo) public tokensPrecision;

    address public rewardsDistributorAddress;
    /// Info of each pool fee.
    uint256 public infinityPassPercent;
    address public infinityPass;
    address public migratorAddress;
    address public termsAndConditionsAddress;

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
        address _rewardsDistributorAddress,
        uint256 _infinityPassPercent,
        address _infinityPass,
        address _migratorAddress,
        address _termsAndConditionsAddress
    ) external initializer {
        rewardsDistributorAddress = _rewardsDistributorAddress;
        infinityPassPercent = _infinityPassPercent;
        infinityPass = _infinityPass;
        migratorAddress = _migratorAddress;
        termsAndConditionsAddress = _termsAndConditionsAddress;

        __Base_init();
        __ReentrancyGuard_init();

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

    function setTermsAndConditionsAddress(
        address _termsAndConditionsAddress
    ) external onlyAdmin nonZeroAddress(_termsAndConditionsAddress) {
        termsAndConditionsAddress = _termsAndConditionsAddress;

        emit SetTermsAndConditionsAddress(_termsAndConditionsAddress);
    }

    function setRewardConfiguration(
        uint256 _pid,
        uint256 rewardPerBlock,
        uint256 updateBlocksInterval
    ) external poolExists(_pid) onlyAdmin {
        _setRewardConfiguration(_pid, rewardPerBlock, updateBlocksInterval);
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
        CollateralUtils.CollateralConfig memory collateralConfig;
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

    function makeMigration(
        uint256 _pid,
        uint256 _amount,
        address _holder
    ) external onlyMigrator poolExists(_pid) {
        UserInfo storage user = userInfo[_pid][_holder];
        PoolInfo storage pool = poolInfo[_pid];
        _updatePool(_pid, 0);

        require(pool.baseToken.balanceOf(_msgSender()) >= _amount, InvalidAmount());

        pool.baseToken.safeTransferFrom(_msgSender(), address(this), _amount);

        pool.totalShares += _amount;

        user.shares += _amount;
        user.blockRewardDebt =
            (user.shares * (pool.accRewardPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        user.productsRewardDebt =
            (user.shares * (pool.rewardsPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;

        emit Stake(_holder, _pid, _amount);
    }

    /**
     * @notice Function to stake token for selected pool
     * @param _pid: pool id
     * @param _amount: token amount
     */
    function stake(
        uint256 _pid,
        uint256 _amount
    ) external nonReentrant whenNotPaused onlyAgreeToTerms(termsAndConditionsAddress) {
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
        uint256 totalShares = pool.totalShares > 0
            ? pool.totalShares
            : tokensPrecision[address(pool.rewardToken)].precision;
        return
            (getRewardPerBlock(_pid) *
                15768000 *
                tokensPrecision[address(pool.rewardToken)].precision) / totalShares;
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
        user.blockRewardDebt =
            (user.shares * (pool.accRewardPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        user.productsRewardDebt =
            (user.shares * (pool.rewardsPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;

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
        user.blockRewardDebt =
            (user.shares * (pool.accRewardPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;
        user.productsRewardDebt =
            (user.shares * (pool.rewardsPerShare)) /
            tokensPrecision[address(pool.rewardToken)].precision;

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

            user.blockRewardDebt =
                (user.shares * (pool.accRewardPerShare)) /
                tokensPrecision[address(pool.rewardToken)].precision;
            user.productsRewardDebt =
                (user.shares * (pool.rewardsPerShare)) /
                tokensPrecision[address(pool.rewardToken)].precision;

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

        uint256 _reward = (block.number - pool.lastRewardBlock) * getRewardPerBlock(_pid);
        pool.accRewardPerShare =
            pool.accRewardPerShare +
            ((_reward * tokensPrecision[address(pool.rewardToken)].precision) / pool.totalShares);
        pool.lastRewardBlock = block.number;
        pool.rewardsAmount += _rewardsAmount;
        pool.rewardsPerShare =
            (pool.rewardsAmount * tokensPrecision[address(pool.rewardToken)].precision) /
            pool.totalShares;

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

        if (block.number < pool.lastRewardBlock || pool.accRewardPerShare == 0) {
            return 0;
        }

        uint256 _accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.totalShares != 0) {
            uint256 _multiplier = block.number - pool.lastRewardBlock;
            uint256 _reward = (_multiplier * getRewardPerBlock(_pid));
            _accRewardPerShare =
                _accRewardPerShare +
                ((_reward * tokensPrecision[address(pool.rewardToken)].precision) /
                    pool.totalShares);
        }

        uint256 blockRewards = ((user.shares * _accRewardPerShare) /
            tokensPrecision[address(pool.rewardToken)].precision) - user.blockRewardDebt;
        uint256 poolRewards = user.shares * pool.rewardsPerShare;
        uint256 productsRewards = (poolRewards /
            tokensPrecision[address(pool.rewardToken)].precision) > user.productsRewardDebt
            ? (poolRewards / tokensPrecision[address(pool.rewardToken)].precision) -
                user.productsRewardDebt
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
