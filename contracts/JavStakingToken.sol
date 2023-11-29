// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./base/BaseUpgradable.sol";

contract JavStakingToken is AccessControlUpgradeable, ERC20BurnableUpgradeable, BaseUpgradable {
    using SafeERC20 for IERC20;
    bytes32 public constant MINTER = "0x01";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC20_init("Jav stDFI", "jstDFI");
        __AccessControl_init();
        __Base_init();

        _grantRole(0x00, msg.sender);
        _grantRole(MINTER, msg.sender);
    }

    /**
     * @notice Function to mint tokens
     * @param account address for mint
     * @param amount Amount of tokens
     */
    function mint(address account, uint256 amount) external onlyRole(MINTER) {
        _mint(account, amount);
    }
}
