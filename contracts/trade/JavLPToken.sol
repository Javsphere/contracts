// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "../base/BaseUpgradable.sol";

contract JavLPToken is ERC20BurnableUpgradeable, BaseUpgradable {
    address public borrowingProvider;

    /* ========== EVENTS ========== */
    event SetBorrowingProvider(address indexed _address);

    modifier onlyBorrowingProvider() {
        require(msg.sender == borrowingProvider, "JavLPToken: only borrowing provider");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC20_init("Javsphere LP", "JavLP");
        __Base_init();
    }

    function setBorrowingProvider(address _borrowingProvider) external onlyOwner {
        borrowingProvider = _borrowingProvider;

        emit SetBorrowingProvider(_borrowingProvider);
    }

    /**
     * @notice Function to mint tokens
     * @param account address for mint
     * @param amount Amount of tokens
     */
    function mint(address account, uint256 amount) external onlyBorrowingProvider {
        _mint(account, amount);
    }
}
