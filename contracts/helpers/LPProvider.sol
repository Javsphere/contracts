// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRewardsDistributor.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IPoolFactory.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPool.sol";

contract LPProvider is BaseUpgradable {
    using SafeERC20 for IERC20;

    IPoolFactory public poolFactory;
    IRouter public router;

    address public botAddress;
    uint256 public burnPercent;
    address public stakingAddress;

    mapping(address => uint256) public lpLockAmount;
    address[] public pools;
    address public rewardsDistributorAddress;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event SetRewardsDistributorAddress(address indexed _address);
    event AddLiquidity(uint256 amountA, uint256 amountB, uint256 liquidity);
    event AddLiquidityETH(uint256 amountToken, uint256 amountETH, uint256 liquidity);
    event WithdrawNative(address indexed to, uint256 amount);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event PoolCreated(address pool);

    modifier onlyBot() {
        require(msg.sender == botAddress, "LPProvider: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    fallback() external payable {}

    function initialize(
        address _poolFactory,
        address _routerAddress,
        address _botAddress
    ) external initializer {
        poolFactory = IPoolFactory(_poolFactory);
        router = IRouter(_routerAddress);

        botAddress = _botAddress;

        __Base_init();
    }

    function setBotAddress(address _address) external nonZeroAddress(_address) onlyAdmin {
        botAddress = _address;

        emit SetBotAddress(_address);
    }

    function setRewardsDistributorAddress(
        address _address
    ) external nonZeroAddress(_address) onlyAdmin {
        rewardsDistributorAddress = _address;

        emit SetRewardsDistributorAddress(_address);
    }

    /**
     * @notice Functon to withdraw amount
     * @param _token token address
     * @param _to recipient address
     * @param _amount amount
     */
    function withdraw(address _token, address _to, uint256 _amount) external onlyAdmin {
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "LPProvider: Invalid amount");
        IERC20(_token).safeTransfer(_to, _amount);

        emit Withdraw(_token, _to, _amount);
    }

    function withdrawNative(address payable _to, uint256 _amount) external onlyAdmin {
        require(address(this).balance >= _amount, "LPProvider: Invalid amount");

        _to.transfer(_amount);

        emit WithdrawNative(_to, _amount);
    }

    function createPool(address tokenA, address tokenB, uint24 fee) external onlyAdmin {
        address _poolAddress = poolFactory.createPool(tokenA, tokenB, fee);
        pools.push(_poolAddress);

        emit PoolCreated(_poolAddress);
    }

    function addLiquidity(
        address lpToken,
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external onlyAdmin {
        require(
            IERC20(tokenA).balanceOf(address(this)) >= amountADesired,
            "LPProvider: Invalid balance - tokenA"
        );
        require(
            IERC20(tokenB).balanceOf(address(this)) >= amountBDesired,
            "LPProvider: Invalid balance - tokenB"
        );

        IERC20(tokenA).safeDecreaseAllowance(address(router), 0);
        IERC20(tokenB).safeDecreaseAllowance(address(router), 0);

        IERC20(tokenA).safeIncreaseAllowance(address(router), amountADesired);
        IERC20(tokenB).safeIncreaseAllowance(address(router), amountBDesired);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            stable,
            amountADesired,
            amountBDesired,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );

        lpLockAmount[lpToken] += liquidity;

        emit AddLiquidity(amountA, amountB, liquidity);
    }

    function claimAndDistributeRewards(address[] calldata _pools) external onlyBot {
        address[] memory _tokens = new address[](_pools.length * 2);
        for (uint256 i = 0; i < _pools.length; ++i) {
            IPool _pool = IPool(_pools[i]);
            (address token0, address token1) = _pool.tokens();
            (uint256 claimed0, uint256 claimed1) = _pool.claimFees();
            if (claimed0 > 0) {
                _tokens = _insertToken(_tokens, token0);
                IERC20(token0).safeTransfer(rewardsDistributorAddress, claimed0);
            }
            if (claimed1 > 0) {
                _tokens = _insertToken(_tokens, token1);
                IERC20(token1).safeTransfer(rewardsDistributorAddress, claimed1);
            }
        }
        IRewardsDistributor(rewardsDistributorAddress).distributeRewards(_tokens);
    }

    function _insertToken(
        address[] memory _tokens,
        address _token
    ) private pure returns (address[] memory) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == _token) {
                return _tokens;
            }

            if (_tokens[i] != _token && _tokens[i] == address(0)) {
                _tokens[i] = _token;

                return _tokens;
            }
        }
        return _tokens;
    }
}
