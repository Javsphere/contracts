// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "./Factory.sol";
import "../../base/BaseUpgradable.sol";
import "./MultiSigWallet.sol";

/// @title Multisignature wallet factory - Allows creation of multisig wallet.
/// @author Stefan George - <stefan.george@consensys.net>
contract MultiSigWalletFactory is Factory, BaseUpgradable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Base_init();
    }

    /*
     * Public functions
     */
    /// @dev Allows verified creation of multisignature wallet.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    /// @return Returns wallet address.
    function create(address[] memory _owners, uint _required) external onlyAdmin returns (address) {
        MultiSigWallet wallet = new MultiSigWallet(_owners, _required);
        register(address(wallet));
        return address(wallet);
    }
}
