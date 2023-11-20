// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract JavNetwork is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    address public adminAddress;
    address public botAddress;

    mapping(bytes32 => string) private cids;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetBotAddress(address indexed _address);
    event SaveCID(string indexed id, string cid);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "JavNetwork: only admin");
        _;
    }

    modifier onlyBot() {
        require(msg.sender == botAddress, "JavNetwork: only bot");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _botAddress) external initializer {
        adminAddress = msg.sender;
        botAddress = _botAddress;

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

    function setAdminAddress(address _address) external onlyAdmin {
        adminAddress = _address;

        emit SetAdminAddress(_address);
    }

    function setBotAddress(address _address) external onlyAdmin {
        botAddress = _address;

        emit SetBotAddress(_address);
    }

    function saveCID(string memory _id, string memory _cid) external onlyBot {
        bytes32 key = keccak256(abi.encodePacked(_id));
        cids[key] = _cid;

        emit SaveCID(_id, _cid);
    }

    function getCID(string memory _key) external view returns (string memory) {
        bytes32 key = keccak256(abi.encodePacked(_key));
        return cids[key];
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private ____gap;
}
