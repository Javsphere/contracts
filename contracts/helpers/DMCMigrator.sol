// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/helpers/ITokenLock.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IERC721Extended.sol";
import "../dmc/IJavStakeX.sol";
import "../dmc/IJavFreezer.sol";

contract DMCMigrator is BaseUpgradable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public tokenLockAddress;
    address public vestingAddress;
    address public vestingFreezerAddress;
    address public stakingAddress;
    address public freezerAddress;
    address public infinityPass;
    mapping(address => uint256) public migratedTime;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _tokenLockAddress,
        address _vestingAddress,
        address _vestingFreezerAddress,
        address _stakingAddress,
        address _freezerAddress,
        address _infinityPass
    ) external initializer {
        token = IERC20(_tokenAddress);
        tokenLockAddress = _tokenLockAddress;
        vestingAddress = _vestingAddress;
        vestingFreezerAddress = _vestingFreezerAddress;
        stakingAddress = _stakingAddress;
        freezerAddress = _freezerAddress;
        infinityPass = _infinityPass;

        __Base_init();
    }

    function migrateFunds(uint256 _tokenID) external whenNotPaused {
        // vesting
        if (ITokenVesting(vestingAddress).holdersVestingCount(_msgSender()) > 0) {
            ITokenVesting(vestingAddress).burnTokens(_msgSender());
        }
        // vesting freezer
        if (ITokenVesting(vestingFreezerAddress).holdersVestingCount(_msgSender()) > 0) {
            ITokenVesting(vestingFreezerAddress).burnTokens(_msgSender());
        }
        // staking
        if (IJavStakeX(stakingAddress).userShares(0, _msgSender()) > 0) {
            IJavStakeX(stakingAddress).burnTokens(0, _msgSender());
        }
        // freezer
        if (IJavFreezer(freezerAddress).userDepositTokens(0, _msgSender()) > 0) {
            IJavFreezer(freezerAddress).burnTokens(0, _msgSender());
        }
        // infinity pass
        if (IERC721Extended(infinityPass).balanceOf(_msgSender()) > 0) {
            IERC721Extended(infinityPass).burn(_tokenID);
        }

        uint256 balance = token.balanceOf(_msgSender());
        if (balance > 0) {
            ITokenLock(tokenLockAddress).lockTokens(_msgSender(), balance);
        }

        migratedTime[_msgSender()] = block.timestamp;
    }

    function migrateUser1(address _user, uint256 _tokenID) external onlyAdmin {
        // vesting
        if (ITokenVesting(vestingAddress).holdersVestingCount(_user) > 0) {
            ITokenVesting(vestingAddress).burnTokens(_user);
        }
        // vesting freezer
        if (ITokenVesting(vestingFreezerAddress).holdersVestingCount(_user) > 0) {
            ITokenVesting(vestingFreezerAddress).burnTokens(_user);
        }
        // staking
        if (IJavStakeX(stakingAddress).userShares(0, _user) > 0) {
            IJavStakeX(stakingAddress).burnTokens(0, _user);
        }
        // infinity pass
        if (IERC721Extended(infinityPass).balanceOf(_user) > 0) {
            IERC721Extended(infinityPass).burn(_tokenID);
        }
    }

    function migrateUser2(
        address _user,
        uint256 depositStart,
        uint256 depositEnd
    ) external onlyAdmin {
        // freezer
        if (IJavFreezer(freezerAddress).userDepositTokens(0, _user) > 0) {
            IJavFreezer(freezerAddress).burnTokensWithRange(0, _user, depositStart, depositEnd);
        }
    }

    function migrateUser3(address _user) external onlyAdmin {
        uint256 balance = token.balanceOf(_user);
        if (balance > 0) {
            ITokenLock(tokenLockAddress).lockTokens(_user, balance);
        }

        migratedTime[_user] = block.timestamp;
    }
}
