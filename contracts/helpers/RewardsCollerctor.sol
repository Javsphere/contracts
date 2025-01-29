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
import "../interfaces/helpers/IJavBurner.sol";

contract RewardsCollector is IRewardsCollector, BaseUpgradable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _allowedAddresses;
    IRouter public swapRouter; // @custom:deprecated
    address public javAddress; // @custom:deprecated
    mapping(address => bool) public tokenPoolFee; // @custom:deprecated
    EnumerableSet.AddressSet private _swapTokens;
    address public javBurner;

    /* ========== EVENTS ========== */
    event AddAllowedAddress(address indexed _address);
    event AddSwapToken(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
    event RemoveSwapToken(address indexed _address);
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

    function getAllowedAddresses() external view returns (address[] memory) {
        return _allowedAddresses.values();
    }

    function getSwapTokens() external view returns (address[] memory) {
        return _swapTokens.values();
    }

    function addAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.add(_address);

        emit AddAllowedAddress(_address);
    }

    function addSwapToken(address _token) external onlyAdmin {
        _swapTokens.add(_token);

        emit AddSwapToken(_token);
    }

    function removeAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.remove(_address);

        emit RemoveAllowedAddress(_address);
    }

    function removeSwapToken(address _token) external onlyAdmin {
        _swapTokens.remove(_token);

        emit RemoveSwapToken(_token);
    }

    function setJavBurner(address _javBurner) external onlyAdmin nonZeroAddress(_javBurner) {
        javBurner = _javBurner;

        emit SetJavBurner(_javBurner);
    }

    function distributeRewards(address[] memory _tokens) external {}

    function swapAndBurn() external onlyAllowedAddresses {
        address _token;
        uint256 _amount;
        for (uint256 i = 0; i < _swapTokens.length(); i++) {
            _token = _swapTokens.at(i);
            _amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(javBurner, _amount);
            IJavBurner(javBurner).swapAndBurn(_token, _amount);
        }
    }
}
