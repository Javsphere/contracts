// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/BaseUpgradable.sol";

contract TestToken is ERC20BurnableUpgradeable, BaseUpgradable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Burnable_init();
        __Base_init();
    }

    /**
     * @notice Function to mint tokens
     * @param account address for mint
     * @param amount Amount of tokens
     */
    function mint(address account, uint256 amount) external onlyAdmin {
        _mint(account, amount);
    }
}
