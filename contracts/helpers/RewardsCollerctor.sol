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

contract RewardsCollector is IRewardsDistributor, BaseUpgradable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _allowedAddresses;

    /* ========== EVENTS ========== */
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
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

    function distributeRewards(address[] memory _tokens) external {}
}
