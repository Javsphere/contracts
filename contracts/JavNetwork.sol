// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "./base/BaseUpgradable.sol";

contract JavNetwork is BaseUpgradable {
    address public botAddress;

    mapping(bytes32 => string) private cids;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event SaveCID(string indexed id, string cid);

    modifier onlyBot() {
        require(msg.sender == botAddress, "JavNetwork: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _botAddress) external initializer {
        botAddress = _botAddress;

        __Base_init();
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
}
