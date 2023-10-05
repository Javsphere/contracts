// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract JavlisToken is ERC20BurnableUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);

    function initialize() external initializer {
        __ERC20_init("Javlis Token", "JAV");
        __Ownable_init();

        emit Initialized(msg.sender, block.number);
    }

    /**
     * @notice Function to mint tokens
     * @param account address for mint
     * @param amount Amount of tokens
     */
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
}
