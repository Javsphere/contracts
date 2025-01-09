// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../interfaces/IRewardsCollector.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IJavFreezer.sol";
import "../interfaces/IJavStakeX.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/IRouter.sol";

contract RewardsCollector is IRewardsCollector, BaseUpgradable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _allowedAddresses;
    IRouter public swapRouter;
    address public javAddress;
    mapping(address => bool) public tokenPoolFee;

    /* ========== EVENTS ========== */
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
    event DistributeRewards(uint256 amount);

    modifier onlyAllowedAddresses() {
        require(_allowedAddresses.contains(msg.sender), "RewardsCollector: only allowed addresses");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory _allowedAddresses_) external initializer {
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

    function setJavAddress(address _javAddress) external onlyAdmin {
        javAddress = _javAddress;

        emit SetJavAddress(_javAddress);
    }

    function setSwapRouterAddress(address _swapRouter) external onlyAdmin {
        swapRouter = IRouter(_swapRouter);

        emit SetSwapRouterAddress(_swapRouter);
    }

    function setTokenPoolFee(address _token, bool _isStable) external onlyAdmin {
        tokenPoolFee[_token] = _isStable;

        emit SetTokenPoolFee(_token, _isStable);
    }

    function distributeRewards(address[] memory _tokens) external {}

    function withdraw(address _token) external onlyAdmin {
        uint256 _amount = IERC20(_token).balanceOf(address(this));

        IERC20(_token).transfer(_msgSender(), _amount);

        emit Withdraw(_token, _msgSender(), _amount);
    }

    function swapAndBurn(address _token) external onlyAllowedAddresses {
        //        uint256 _swapAmount = IERC20(_token).balanceOf(address(this));
        //        require(_swapAmount > 0, InvalidSwapAmount());
        //
        //        _swapToken(_token, javAddress, _swapAmount);
        //
        //        uint256 _burnAmount = IERC20(javAddress).balanceOf(address(this));
        //        IERC20Extended(javAddress).burn(_burnAmount);
        //
        //        emit SwapAndBurn(_token, _swapAmount, _burnAmount);
    }

    function _swapToken(address _tokenIn, address _tokenOut, uint256 _amount) private {
        IERC20(_tokenIn).safeDecreaseAllowance(address(swapRouter), 0);
        IERC20(_tokenIn).safeIncreaseAllowance(address(swapRouter), _amount);

        IRouter.Route[] memory route = new IRouter.Route[](1);
        route[0] = IRouter.Route({
            from: _tokenIn,
            to: _tokenOut,
            stable: tokenPoolFee[_tokenIn],
            factory: address(0)
        });

        swapRouter.swapExactTokensForTokens(
            _amount,
            0,
            route,
            address(this),
            block.timestamp + 1000
        );
    }
}
