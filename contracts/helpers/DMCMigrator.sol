// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/helpers/ITokenLock.sol";
import "../interfaces/ITokenVesting.sol";

contract DMCMigrator is BaseUpgradable {
    IERC20 public token;
    address public tokenLockAddress;
    address public vestingAddress;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _tokenLockAddress,
        address _vestingAddress
    ) external initializer {
        token = IERC20(_tokenAddress);
        tokenLockAddress = _tokenLockAddress;
        vestingAddress = _vestingAddress;

        __Base_init();
    }

    function migrateFunds() external {
        uint256 balance = token.balanceOf(_msgSender());
        if (balance > 0) {
            ITokenLock(tokenLockAddress).lockTokens(_msgSender(), balance);
        }
        if (ITokenVesting(vestingAddress).holdersVestingCount(_msgSender()) > 0) {
            ITokenVesting(vestingAddress).burnTokens(_msgSender());
        }
    }
}
