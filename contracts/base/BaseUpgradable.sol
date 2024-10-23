// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract BaseUpgradable is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    address public adminAddress;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);

    error AddressZero();

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "BaseUpgradable: only admin");
        _;
    }
    modifier nonZeroAddress(address _address) {
        require(_address != address(0), AddressZero());
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function __Base_init() internal onlyInitializing {
        adminAddress = msg.sender;

        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();

        emit Initialized(msg.sender, block.number);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setAdminAddress(address _address) external nonZeroAddress(_address) onlyAdmin {
        adminAddress = _address;

        emit SetAdminAddress(_address);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private ____gap;
}
