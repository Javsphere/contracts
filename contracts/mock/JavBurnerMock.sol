pragma solidity ^0.8.24;
import "hardhat/console.sol";

import "../base/BaseUpgradable.sol";
import "../interfaces/helpers/IJavBurner.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/helpers/IGeneralErrors.sol";

contract JavBurnerMock is IJavBurner, BaseUpgradable, IGeneralErrors {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Base_init();
    }

    function swapAndBurn(address _token, uint256 _swapAmount) external {
        IERC20Extended(_token).burn(_swapAmount);
        emit SwapAndBurn(_token, _swapAmount, _swapAmount);
    }
}
