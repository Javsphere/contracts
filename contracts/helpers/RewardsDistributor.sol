// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../interfaces/IRewardsDistributor.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IJavFreezer.sol";
import "../interfaces/IJavStakeX.sol";
import "../base/BaseUpgradable.sol";

contract RewardsDistributor is IRewardsDistributor, BaseUpgradable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _allowedAddresses;

    ISwapRouter public swapRouter;

    address public javAddress;
    address public stakingAddress;
    address public freezerAddress;

    uint256 public burnPercent;
    uint256 public freezerPercent;

    mapping(address => uint256) public tokenPoolFee;

    /* ========== EVENTS ========== */
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
    event SetPercents(uint256 burnPercent, uint256 freezerPercent);
    event SetTokenPoolFee(address token, uint256 fee);
    event DistributeRewards(uint256 amount);

    modifier onlyAllowedAddresses() {
        require(
            _allowedAddresses.contains(msg.sender),
            "RewardsDistributor: only allowed addresses"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _javAddress,
        address _swapRouter,
        address _stakingAddress,
        address _freezerAddress,
        uint256 _burnPercent,
        uint256 _freezerPercent,
        address[] memory _allowedAddresses_
    ) external initializer {
        javAddress = _javAddress;
        stakingAddress = _stakingAddress;
        freezerAddress = _freezerAddress;

        burnPercent = _burnPercent;
        freezerPercent = _freezerPercent;

        swapRouter = ISwapRouter(_swapRouter);

        for (uint256 i = 0; i < _allowedAddresses_.length; i++) {
            _allowedAddresses.add(_allowedAddresses_[i]);
        }

        __Base_init();
    }

    function addAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.add(_address);

        emit AddAllowedAddress(_address);
    }

    function removeAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.remove(_address);

        emit RemoveAllowedAddress(_address);
    }

    function setPercents(uint256 _burnPercent, uint256 _freezerPercent) external onlyAdmin {
        burnPercent = _burnPercent;
        freezerPercent = _freezerPercent;

        emit SetPercents(burnPercent, freezerPercent);
    }

    function setTokenPoolFee(address _token, uint256 _fee) external onlyAdmin {
        tokenPoolFee[_token] = _fee;

        emit SetTokenPoolFee(_token, _fee);
    }

    function distributeRewards(address[] memory _tokens) external onlyAllowedAddresses {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address _tokenIn = _tokens[i];
            if (_tokenIn != javAddress) {
                _swapToken(
                    _tokenIn,
                    javAddress,
                    IERC20(_tokenIn).balanceOf(address(this)),
                    tokenPoolFee[_tokenIn]
                );
            }
        }
        _distributeRewards();
    }

    function _swapToken(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        uint256 _poolFee
    ) private {
        IERC20(_tokenIn).safeDecreaseAllowance(address(swapRouter), 0);
        IERC20(_tokenIn).safeIncreaseAllowance(address(swapRouter), _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: uint24(_poolFee),
            recipient: address(this),
            deadline: block.timestamp + 500,
            amountIn: _amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactInputSingle(params);
    }

    function _distributeRewards() private {
        uint256 _amount = IERC20(javAddress).balanceOf(address(this));
        uint256 _burnAmount = (_amount * burnPercent) / 100;
        uint256 _rewardsAmount = _amount - _burnAmount;

        //1. Burn jav tokens
        IERC20Extended(javAddress).burn(_burnAmount);

        //2. freezer rewards
        uint256 _freezerRewards = (_rewardsAmount * freezerPercent) / 100;
        IERC20(javAddress).transfer(freezerAddress, _freezerRewards);
        IJavFreezer(freezerAddress).addRewards(0, _freezerRewards);

        //3. staking rewards
        uint256 _stakingRewards = _rewardsAmount - _freezerRewards;
        IERC20(javAddress).transfer(stakingAddress, _stakingRewards);
        IJavStakeX(stakingAddress).addRewards(0, _stakingRewards);

        emit DistributeRewards(_rewardsAmount);
    }
}
