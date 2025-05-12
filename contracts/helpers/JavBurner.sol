// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/helpers/IJavBurner.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/helpers/IGeneralErrors.sol";

contract JavBurner is IJavBurner, IGeneralErrors, BaseUpgradable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _allowedAddresses;
    IRouter public swapRouter;
    address public javAddress;

    mapping(address => IRouter.Route[]) public swapRoute;

    modifier onlyAllowedAddresses() {
        require(_allowedAddresses.contains(msg.sender), "JavBurner: only allowed addresses");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _javAddress,
        address _swapRouterAddress,
        address[] memory _allowedAddresses_
    ) external initializer {
        javAddress = _javAddress;
        swapRouter = IRouter(_swapRouterAddress);
        for (uint256 i = 0; i < _allowedAddresses_.length; i++) {
            _allowedAddresses.add(_allowedAddresses_[i]);
        }

        __Base_init();
    }

    function getAllowedAddresses() external view returns (address[] memory) {
        return _allowedAddresses.values();
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

    function setSwapRoute(address _token, IRouter.Route[] calldata _route) external onlyAdmin {
        require(_route.length != 0, InvalidInputLength());

        swapRoute[_token] = _route;

        emit SetSwapRoute(_token, _route);
    }

    function swapAndBurn(address _token, uint256 _swapAmount) external onlyAllowedAddresses {
        require(IERC20(_token).balanceOf(address(this)) >= _swapAmount, InvalidAmount());

        if (_token != javAddress) {
            IRouter.Route[] memory route = swapRoute[_token];
            require(route.length != 0, ZeroValue());

            IERC20(_token).safeDecreaseAllowance(address(swapRouter), 0);
            IERC20(_token).safeIncreaseAllowance(address(swapRouter), _swapAmount);

            swapRouter.swapExactTokensForTokens(
                _swapAmount,
                0,
                route,
                address(this),
                block.timestamp + 1
            );
        }

        uint256 _burnAmount = IERC20(javAddress).balanceOf(address(this));
        IERC20Extended(javAddress).burn(_burnAmount);

        emit SwapAndBurn(_token, _swapAmount, _burnAmount);
    }
}
