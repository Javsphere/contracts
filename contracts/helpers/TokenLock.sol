// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/helpers/ITokenLock.sol";

contract TokenLock is ITokenLock, BaseUpgradable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    mapping(address => uint256) public tokenAmount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenAddress) external initializer {
        token = IERC20(_tokenAddress);

        __Base_init();
    }

    function lockTokens(uint256 _amount) external {
        require(token.balanceOf(_msgSender()) >= _amount, InvalidAmount());

        token.safeTransferFrom(_msgSender(), address(this), _amount);
        tokenAmount[_msgSender()] += _amount;

        emit LockTokens(_msgSender(), _amount);
    }
}
