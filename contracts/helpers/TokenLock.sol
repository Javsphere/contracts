// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/helpers/ITokenLock.sol";

contract TokenLock is ITokenLock, BaseUpgradable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public migratorAddress;
    mapping(address => uint256) public tokenAmount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyMigrator() {
        require(msg.sender == migratorAddress, NotAllowed());
        _;
    }

    function initialize(address _tokenAddress, address _migrator) external initializer {
        token = IERC20(_tokenAddress);
        migratorAddress = _migrator;

        __Base_init();
    }

    function setMigratorAddress(address _address) external onlyAdmin {
        migratorAddress = _address;

        emit SetMigratorAddress(_address);
    }

    function lockTokens(address _from, uint256 _amount) external onlyMigrator {
        require(token.balanceOf(_from) >= _amount, InvalidAmount());

        token.safeTransferFrom(_from, address(this), _amount);
        tokenAmount[_from] += _amount;

        emit LockTokens(_from, _amount);
    }
}
