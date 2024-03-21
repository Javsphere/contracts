// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVanillaRouter02.sol";
import "./interfaces/IVanillaPair.sol";
import "./helpers/RewardRateConfigurable.sol";
import "./base/BaseUpgradable.sol";

contract JavFarming is BaseUpgradable, ReentrancyGuardUpgradeable, RewardRateConfigurable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Info of each user
     * @param totalDepositTokens total amount of deposits in tokens
     * @param lpTokensAmount: How many LP tokens the user has provided
     * @param rewardDebt: Reward debt. See explanation below
     * @param totalClaims: total amount of claimed tokens
     */
    struct UserInfo {
        uint256 totalDepositTokens;
        uint256 lpTokensAmount;
        uint256 rewardDebt;
        uint256 totalClaims;
    }

    /**
     * @notice Info of each pool
     * @param lpToken: Address of LP token contract
     * @param allocPoint: How many allocation points assigned to this pool. rewards to distribute per block
     * @param lastRewardBlock: Last block number that rewards distribution occurs
     * @param accRewardPerShare: Accumulated rewards per share, times 1e18. See below
     */
    struct PoolInfo {
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
    }

    struct AddLiquidityResult {
        uint256 baseTokensStaked;
        uint256 javTokensStaked;
        uint256 lpTokensReceived;
        uint256 baseTokensRemainder;
        uint256 javTokensRemainder;
    }

    EnumerableSet.AddressSet private _allowedPairs;
    /// The reward token
    address public rewardToken;
    /// Info of each pool.
    PoolInfo[] public poolInfo;
    /// Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => bool) public isPoolExist;
    /// Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    /// The block number when reward mining starts.
    uint256 public startBlock;
    address public routerAddress;
    address public wdfiAddress;
    address[] public rewardTokenToWDFI;

    /* ========== EVENTS ========== */
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event NewPoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);
    event PoolAllocPointUpdated(uint256 indexed pid, uint256 allocPoint);
    event StartBlockUpdated(uint256 newValue);
    event PoolCommissionUpdated(uint256 newValue);
    event SetRewardTokenAddress(address indexed _address);
    event SetWDFIAddress(address indexed _address);
    event SetRouterAddress(address indexed _address);
    event AddAllowedPair(address indexed _address);
    event RemoveAllowedPair(address indexed _address);

    modifier poolExists(uint256 _pid) {
        require(_pid < poolInfo.length, "JavFarming: Unknown pool");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    fallback() external payable {}

    function initialize(
        address _rewardToken,
        address _wdfiAddress,
        address _routerAddress,
        uint256 _rewardPerBlock,
        uint256 _startBlock
    ) external initializer {
        rewardToken = _rewardToken;
        wdfiAddress = _wdfiAddress;
        routerAddress = _routerAddress;
        startBlock = _startBlock;
        rewardTokenToWDFI = [_rewardToken, wdfiAddress];
        _allowedPairs.add(wdfiAddress);

        __Base_init();
        __ReentrancyGuard_init();
        __RewardRateConfigurable_init(_rewardPerBlock, 864000);
    }

    /**
     * @notice Function to add allowed pair
     * @param _address: address of reward token
     */
    function addAllowedPair(address _address) external onlyAdmin {
        _allowedPairs.add(_address);

        emit AddAllowedPair(_address);
    }

    /**
     * @notice Function to remove allowed pair
     * @param _address: address of reward token
     */
    function removeAllowedPair(address _address) external onlyAdmin {
        _allowedPairs.remove(_address);

        emit RemoveAllowedPair(_address);
    }

    /**
     * @notice Function to set reward token
     * @param _address: address of reward token
     */
    function setRewardToken(address _address) external onlyAdmin {
        rewardToken = _address;
        rewardTokenToWDFI = [_address, wdfiAddress];

        emit SetRewardTokenAddress(_address);
    }

    function setStartBlock(uint256 _startBlock) external onlyAdmin {
        startBlock = _startBlock;

        emit StartBlockUpdated(_startBlock);
    }

    function setWDFIAddress(address _address) external onlyAdmin {
        _allowedPairs.remove(wdfiAddress);
        wdfiAddress = _address;
        rewardTokenToWDFI[1] = _address;
        _allowedPairs.add(wdfiAddress);

        emit SetWDFIAddress(_address);
    }

    function setRouterAddress(address _address) external onlyAdmin {
        routerAddress = _address;

        emit SetRouterAddress(_address);
    }

    /**
     * @notice Function to set amount of reward per block
     */
    function setRewardConfiguration(
        uint256 _rewardPerBlock,
        uint256 _rewardUpdateBlocksInterval
    ) external onlyAdmin {
        massUpdatePools();

        _setRewardConfiguration(_rewardPerBlock, _rewardUpdateBlocksInterval);
    }

    function setlastRewardBlock(
        uint256 _pid,
        uint256 _lastRewardBlock,
        uint256 _accRewardPerShare
    ) external onlyAdmin {
        poolInfo[_pid].lastRewardBlock = _lastRewardBlock;
        poolInfo[_pid].accRewardPerShare = _accRewardPerShare;
    }

    /**
     * @notice Add a new lp to the pool. Can only be called by the owner
     * @param _allocPoint: allocPoint for new pool
     * @param _lpToken: address of lpToken for new pool
     */
    function addPool(uint256 _allocPoint, address _lpToken) external onlyAdmin {
        require(!isPoolExist[address(_lpToken)], "JavFarming: Duplicate pool");
        require(_isSupportedLP(_lpToken), "JavFarming: Unsupported liquidity pool");

        massUpdatePools();

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0
            })
        );

        isPoolExist[address(_lpToken)] = true;

        uint256 pid = poolInfo.length - 1;

        emit NewPoolAdded(pid, _lpToken, _allocPoint);
    }

    /**
     * @notice Update the given pool's reward allocation point. Can only be called by the owner
     */
    function setAllocationPoint(
        uint256 _pid,
        uint256 _allocPoint
    ) external onlyAdmin poolExists(_pid) {
        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        emit PoolAllocPointUpdated(_pid, _allocPoint);
    }

    /**
     * @notice Deposit LP tokens to JavFarming for reward allocation
     * @param _pid: pool ID on which LP tokens should be deposited
     * @param _amount: the amount of LP tokens that should be deposited
     */
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant poolExists(_pid) {
        updatePool(_pid);

        require(
            IERC20(poolInfo[_pid].lpToken).balanceOf(msg.sender) >= _amount,
            "JavFarming: Insufficient LP balance"
        );

        IERC20(poolInfo[_pid].lpToken).safeTransferFrom(msg.sender, address(this), _amount);

        IVanillaPair pair = IVanillaPair(poolInfo[_pid].lpToken);

        uint256 totalSupply = pair.totalSupply();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveRewToken, uint256 reserveBaseToken) = pair.token0() == rewardToken
            ? (reserve0, reserve1)
            : (reserve1, reserve0);

        AddLiquidityResult memory liquidityData;

        liquidityData.lpTokensReceived = _amount;
        liquidityData.baseTokensStaked = (_amount * reserveBaseToken) / totalSupply;
        liquidityData.javTokensStaked = (_amount * reserveRewToken) / totalSupply;

        _updateUserInfo(_pid, msg.sender, liquidityData);

        emit Deposit(msg.sender, _pid, liquidityData.lpTokensReceived);
    }

    /**
     * @notice Function which take ETH & tokens or tokens & tokens, add liquidity with provider and deposit given LP's
     * @param _pid: pool ID where we want deposit
     * @param _baseTokenAmount: amount of token pool base token for staking ( use 0 for DFI pool)
     * @param _javTokenAmount: amount of JAV token for staking
     * @param _amountAMin: bounds the extent to which the B/A price can go up before the transaction reverts.
        Must be <= amountADesired.
     * @param _amountBMin: bounds the extent to which the A/B price can go up before the transaction reverts.
        Must be <= amountBDesired
     * @param _minAmountOutA: the minimum amount of output A tokens that must be received
        for the transaction not to revert
     * @param _deadline transaction deadline timestamp
     */
    function speedStake(
        uint256 _pid,
        uint256 _baseTokenAmount,
        uint256 _javTokenAmount,
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _minAmountOutA,
        uint256 _deadline
    ) external payable nonReentrant whenNotPaused poolExists(_pid) {
        require(
            _baseTokenAmount == 0 || msg.value == 0,
            "JavFarming: Cannot pass both DFI and ERC-20 assets"
        );

        updatePool(_pid);

        if (_javTokenAmount > 0) {
            IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _javTokenAmount);
        }

        _deposit(
            _pid,
            _baseTokenAmount,
            _javTokenAmount,
            _amountAMin,
            _amountBMin,
            _minAmountOutA,
            _deadline
        );
    }

    /**
     * @notice Function which send accumulated reward tokens to messege sender
     * @param _pid: pool ID from which the accumulated reward tokens should be received
     */
    function harvest(uint256 _pid) external nonReentrant poolExists(_pid) {
        _harvest(_pid, msg.sender);
    }

    /**
     * @notice Function which send accumulated reward tokens to messege sender from all pools
     */
    function harvestAll() external nonReentrant {
        uint256 length = poolInfo.length;

        for (uint256 pid = 0; pid < length; ++pid) {
            if (poolInfo[pid].allocPoint > 0) {
                _harvest(pid, msg.sender);
            }
        }
    }

    /**
     * @notice Function which withdraw LP tokens to messege sender with the given amount
     * @param _pid: pool ID from which the LP tokens should be withdrawn
     */
    function withdraw(uint256 _pid) external nonReentrant poolExists(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 withdrawAmount = user.lpTokensAmount;

        updatePool(_pid);

        uint256 pending = (withdrawAmount * pool.accRewardPerShare) / 1e18 - user.rewardDebt;

        user.totalClaims += pending;
        IERC20(rewardToken).safeTransfer(msg.sender, pending);

        emit Harvest(msg.sender, _pid, pending);

        user.lpTokensAmount = 0;
        user.rewardDebt = 0;
        user.totalDepositTokens = 0;

        IERC20(pool.lpToken).safeTransfer(msg.sender, withdrawAmount);

        emit Withdraw(msg.sender, _pid, withdrawAmount);
    }

    /**
     * @notice Function to get all allowed pairs addresses
     */
    function getAllowedPairs() external view returns (address[] memory) {
        return _allowedPairs.values();
    }

    /**
     * @notice View function to see total pending rewards on frontend
     * @param _user: user address for which reward must be calculated
     * @return total Return reward for user
     */
    function pendingRewardTotal(address _user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 pid = 0; pid < poolInfo.length; ++pid) {
            total += _getPendingReward(pid, _user);
        }

        return total;
    }

    /**
     * @notice View function to get pending rewards
     * @param _pid: pool ID for which reward must be calculated
     * @param _user: user address for which reward must be calculated
     * @return Return reward for user
     */
    function pendingReward(
        uint256 _pid,
        address _user
    ) external view poolExists(_pid) returns (uint256) {
        return _getPendingReward(_pid, _user);
    }

    /**
     * @notice Returns pool numbers
     */
    function getPoolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice Update reward vairables for all pools
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;

        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date
     * @param _pid: pool ID for which the reward variables should be updated
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));

        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = (multiplier * pool.allocPoint) / totalAllocPoint;

        pool.accRewardPerShare = pool.accRewardPerShare + ((reward * 1e18) / lpSupply);
        pool.lastRewardBlock = block.number;

        // Update rewardPerBlock AFTER pool was updated
        _updateRewardPerBlock();
    }

    /**
     * @param _from: block block from which the reward is calculated
     * @param _to: block block before which the reward is calculated
     * @return Return reward multiplier over the given _from to _to block
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return (getRewardPerBlock() * (_to - _from));
    }

    /**
     * @notice Contract private function to process user deposit.
        1. Transfer pool base tokens to this contract if _baseTokenAmount > 0
        2. Swap jav tokens for pool base token
        3. Provide liquidity using 50/50 split of pool base tokens:
            a. 50% of pool base tokens used as is
            b. 50% used to buy JAV tokens
            c. Add both amounts to liquidity pool
        5. Update user deposit information
     * @param _pid pool id
     * @param _baseTokenAmount amount of pool base tokens provided by user
     * @param _javTokenAmount amount if JAV tokens provided by user
     * @param _amountAMin: bounds the extent to which the B/A price can go up before the transaction reverts.
        Must be <= amountADesired.
     * @param _amountBMin: bounds the extent to which the A/B price can go up before the transaction reverts.
        Must be <= amountBDesired
     * @param _minAmountOutA: the minimum amount of output A tokens that must be received
        for the transaction not to revert
     * @param _deadline transaction deadline timestamp
     */
    function _deposit(
        uint256 _pid,
        uint256 _baseTokenAmount,
        uint256 _javTokenAmount,
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _minAmountOutA,
        uint256 _deadline
    ) private {
        IVanillaPair lpToken = IVanillaPair(address(poolInfo[_pid].lpToken));
        address poolBaseToken = _getPoolBaseTokenFromPair(lpToken);
        uint256 poolBaseTokenAmount = _isDFIPool(lpToken) ? msg.value : _baseTokenAmount;
        uint256 javTokenAmount = _javTokenAmount;

        bool splitAndSwap = javTokenAmount == 0 ? true : false;

        if (_isDFIPool(lpToken)) {
            require(_baseTokenAmount == 0, "JavFarming: only DFI tokens expected");
        } else {
            require(msg.value == 0, "JavFarming: only BEP-20 tokens expected");
        }

        if (_baseTokenAmount > 0) {
            IERC20(poolBaseToken).safeTransferFrom(msg.sender, address(this), _baseTokenAmount);
        }

        if (javTokenAmount > 0 && poolBaseTokenAmount == 0) {
            IERC20(rewardToken).safeDecreaseAllowance(routerAddress, 0);
            IERC20(rewardToken).safeIncreaseAllowance(routerAddress, javTokenAmount);

            poolBaseTokenAmount = _swapTokens(
                rewardToken,
                poolBaseToken,
                javTokenAmount,
                0,
                address(this),
                _deadline
            );

            javTokenAmount = 0;
            splitAndSwap = true;
        }

        AddLiquidityResult memory result = _addLiquidity(
            poolBaseToken,
            poolBaseTokenAmount,
            javTokenAmount,
            _amountAMin,
            _amountBMin,
            _minAmountOutA,
            _deadline,
            splitAndSwap
        );

        _updateUserInfo(_pid, msg.sender, result);
        _refundRemainderTokens(msg.sender, poolBaseToken, result);

        emit Deposit(msg.sender, _pid, result.lpTokensReceived);
    }

    /**
     * @notice Function to swap exact amount of tokens A for tokens B
     * @param inputToken have token address
     * @param outputToken want token address
     * @param inputAmount have token amount
     * @param amountOutMin the minimum amount of output tokens that must be
        received for the transaction not to revert.
     * @param receiver want tokens receiver address
     * @param deadline swap transaction deadline
     * @return uint256 amount of want tokens received
     */
    function _swapTokens(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 amountOutMin,
        address receiver,
        uint256 deadline
    ) private returns (uint256) {
        require(inputToken != outputToken, "JavFarming: Invalid swap path");

        address[] memory path = new address[](2);

        path[0] = inputToken;
        path[1] = outputToken;

        uint256[] memory swapResult;

        if (inputToken == wdfiAddress) {
            swapResult = IVanillaRouter02(routerAddress).swapExactETHForTokens{value: inputAmount}(
                amountOutMin,
                path,
                receiver,
                deadline
            );
        } else if (outputToken == wdfiAddress) {
            swapResult = IVanillaRouter02(routerAddress).swapExactTokensForETH(
                inputAmount,
                amountOutMin,
                path,
                receiver,
                deadline
            );
        } else {
            swapResult = IVanillaRouter02(routerAddress).swapExactTokensForTokens(
                inputAmount,
                amountOutMin,
                path,
                receiver,
                deadline
            );
        }

        return swapResult[1];
    }

    function _addLiquidity(
        address _basePoolToken,
        uint256 _baseTokenAmount,
        uint256 _javTokenAmount,
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _minAmountOut,
        uint256 _deadline,
        bool splitAndSwap
    ) private returns (AddLiquidityResult memory result) {
        uint256 baseTokensToLpAmount = _baseTokenAmount;
        uint256 javToLpAmount = _javTokenAmount;

        if (_basePoolToken == wdfiAddress) {
            if (splitAndSwap) {
                uint256 swapAmount = baseTokensToLpAmount / 2;

                javToLpAmount = _swapTokens(
                    _basePoolToken,
                    rewardToken,
                    swapAmount,
                    _minAmountOut,
                    address(this),
                    _deadline
                );

                baseTokensToLpAmount -= swapAmount;
            }
            require(
                baseTokensToLpAmount >= _amountAMin,
                "JavFarming: insufficient pool base tokens"
            );
            require(javToLpAmount >= _amountBMin, "JavFarming: insufficient JAV tokens");
            IERC20(rewardToken).safeDecreaseAllowance(routerAddress, 0);
            IERC20(rewardToken).safeIncreaseAllowance(routerAddress, javToLpAmount);

            (
                result.javTokensStaked,
                result.baseTokensStaked,
                result.lpTokensReceived
            ) = IVanillaRouter02(routerAddress).addLiquidityETH{value: baseTokensToLpAmount}(
                rewardToken,
                javToLpAmount,
                _amountBMin,
                _amountAMin,
                address(this),
                _deadline
            );
        } else {
            if (splitAndSwap) {
                uint256 swapAmount = baseTokensToLpAmount / 2;

                IERC20(_basePoolToken).safeDecreaseAllowance(routerAddress, 0);
                IERC20(_basePoolToken).safeIncreaseAllowance(routerAddress, swapAmount);

                javToLpAmount = _swapTokens(
                    _basePoolToken,
                    rewardToken,
                    swapAmount,
                    _minAmountOut,
                    address(this),
                    _deadline
                );

                baseTokensToLpAmount -= swapAmount;
            }

            IERC20(_basePoolToken).safeDecreaseAllowance(routerAddress, 0);
            IERC20(rewardToken).safeDecreaseAllowance(routerAddress, 0);

            IERC20(_basePoolToken).safeIncreaseAllowance(routerAddress, baseTokensToLpAmount);
            IERC20(rewardToken).safeIncreaseAllowance(routerAddress, javToLpAmount);

            (
                result.baseTokensStaked,
                result.javTokensStaked,
                result.lpTokensReceived
            ) = IVanillaRouter02(routerAddress).addLiquidity(
                _basePoolToken,
                rewardToken,
                baseTokensToLpAmount,
                javToLpAmount,
                _amountAMin,
                _amountBMin,
                address(this),
                _deadline
            );
        }

        if (baseTokensToLpAmount > result.baseTokensStaked) {
            result.baseTokensRemainder = baseTokensToLpAmount - result.baseTokensStaked;
        }

        if (javToLpAmount > result.javTokensStaked) {
            result.javTokensRemainder = javToLpAmount - result.javTokensStaked;
        }
    }

    /**
     * @notice Function for updating user info
     */
    function _updateUserInfo(
        uint256 _pid,
        address _from,
        AddLiquidityResult memory liquidityData
    ) private {
        UserInfo storage user = userInfo[_pid][_from];
        address poolBaseToken = _getPoolBaseTokenFromPair(
            IVanillaPair(address(poolInfo[_pid].lpToken))
        );

        _harvest(_pid, _from);

        user.totalDepositTokens += liquidityData.baseTokensStaked;
        user.totalDepositTokens += _getJavInBaseTokensAmount(
            liquidityData.javTokensStaked,
            poolBaseToken
        );

        user.lpTokensAmount += liquidityData.lpTokensReceived;
        user.rewardDebt = (user.lpTokensAmount * poolInfo[_pid].accRewardPerShare) / 1e18;
    }

    /**
     * @notice Private function which send accumulated reward tokens to givn address
     * @param _pid: pool ID from which the accumulated reward tokens should be received
     * @param _from: Recievers address
     */
    function _harvest(uint256 _pid, address _from) private poolExists(_pid) {
        UserInfo storage user = userInfo[_pid][_from];

        if (user.lpTokensAmount > 0) {
            updatePool(_pid);

            uint256 accRewardPerShare = poolInfo[_pid].accRewardPerShare;
            uint256 pending = (user.lpTokensAmount * accRewardPerShare) / 1e18 - user.rewardDebt;

            user.totalClaims += pending;
            IERC20(rewardToken).safeTransfer(_from, pending);

            user.rewardDebt = (user.lpTokensAmount * accRewardPerShare) / 1e18;

            emit Harvest(_from, _pid, pending);
        }
    }

    /**
     * @notice Check if provided VamillaSwap Pair contains WDFItoken
     * @param pair VamillaSwap pair contract
     * @return bool true if provided pair is WDFI/<Token> or <Token>/WDFI pair
                    false otherwise
     */
    function _isDFIPool(IVanillaPair pair) private view returns (bool) {
        IVanillaRouter02 router = IVanillaRouter02(routerAddress);

        return pair.token0() == router.WETH() || pair.token1() == router.WETH();
    }

    function _isSupportedLP(address pairAddress) private view returns (bool) {
        IVanillaPair pair = IVanillaPair(pairAddress);
        require(
            rewardToken == pair.token0() || rewardToken == pair.token1(),
            "JavFarming: not a JAV pair"
        );

        address baseToken = _getPoolBaseTokenFromPair(pair);

        return _allowedPairs.contains(baseToken);
    }

    /**
     * @notice Get pool base token from VanillaSwap Pair.
     * @param pair VanillaSwap pair contract
     * @return address pool base token address
     */
    function _getPoolBaseTokenFromPair(IVanillaPair pair) private view returns (address) {
        return pair.token0() == rewardToken ? pair.token1() : pair.token0();
    }

    function _refundRemainderTokens(
        address user,
        address poolBaseToken,
        AddLiquidityResult memory liquidityData
    ) private {
        if (liquidityData.baseTokensRemainder > 0) {
            if (poolBaseToken == wdfiAddress) {
                payable(user).transfer(liquidityData.baseTokensRemainder);
            } else {
                IERC20(poolBaseToken).safeTransfer(user, liquidityData.baseTokensRemainder);
            }
        }

        if (liquidityData.javTokensRemainder > 0) {
            IERC20(rewardToken).safeTransfer(user, liquidityData.javTokensRemainder);
        }
    }

    function _getJavInBaseTokensAmount(
        uint256 javAmount,
        address poolBaseToken
    ) private view returns (uint256) {
        if (poolBaseToken == wdfiAddress) {
            return IVanillaRouter02(routerAddress).getAmountsOut(javAmount, rewardTokenToWDFI)[1];
        } else {
            address[] memory path = new address[](2);

            path[0] = rewardToken;
            path[1] = poolBaseToken;

            return IVanillaRouter02(routerAddress).getAmountsOut(javAmount, path)[1];
        }
    }

    /**
     * @notice Private view function to get pending rewards
     * @param _pid: pool ID for which reward must be calculated
     * @param _user: user address for which reward must be calculated
     * @return Return reward for user
     */
    function _getPendingReward(
        uint256 _pid,
        address _user
    ) private view poolExists(_pid) returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];

        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward = (multiplier * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare = accRewardPerShare + ((reward * 1e18) / lpSupply);
        }

        return (user.lpTokensAmount * accRewardPerShare) / 1e18 - user.rewardDebt;
    }
}
