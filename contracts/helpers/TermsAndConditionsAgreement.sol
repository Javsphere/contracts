// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../interfaces/helpers/ITermsAndConditionsAgreement.sol";
import "../interfaces/helpers/IGeneralErrors.sol";
import "../base/BaseUpgradable.sol";

contract TermsAndConditionsAgreement is
    ITermsAndConditionsAgreement,
    IGeneralErrors,
    BaseUpgradable
{
    uint256 public agreementsId;
    mapping(uint256 => mapping(address => uint256)) public agreements;
    string public agreementsUrl;

    event UpdateTerms(string agreementsUrl, uint256 agreementsId);
    event UserAgreed(address indexed user, uint256 timestamp, uint256 agreementsId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string calldata _agreementsUrl) external initializer {
        agreementsUrl = _agreementsUrl;

        __Base_init();
    }

    function updateTerms(string calldata _newAgreementsUrl) external onlyAdmin {
        agreementsUrl = _newAgreementsUrl;
        agreementsId++;

        emit UpdateTerms(_newAgreementsUrl, agreementsId);
    }

    function hasAgreed(address user) external view returns (bool) {
        return agreements[agreementsId][user] != 0;
    }

    function agreeToTerms() external {
        require(agreements[agreementsId][_msgSender()] == 0, AlreadyExists());

        agreements[agreementsId][_msgSender()] = block.timestamp;

        emit UserAgreed(_msgSender(), block.timestamp, agreementsId);
    }
}
