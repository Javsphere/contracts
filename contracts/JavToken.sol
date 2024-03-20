// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./base/BaseUpgradable.sol";

contract JavToken is ERC20CappedUpgradeable, BaseUpgradable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _cap) external initializer {
        __ERC20_init("Javsphere", "JAV");
        __ERC20Capped_init(_cap);
        __Base_init();
    }

    /**
     * @notice Function to mint tokens
     * @param account address for mint
     * @param amount Amount of tokens
     */
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /**
     * @dev Destroys a `value` amount of tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 value) external {
        _burn(_msgSender(), value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, deducting from
     * the caller's allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `value`.
     */
    function burnFrom(address account, uint256 value) external {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }
}
