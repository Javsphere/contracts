// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../access/MultiSignatureUpgradeable.sol";

contract MultiSignMock is OwnableUpgradeable, MultiSignatureUpgradeable {
    function initialize(
        uint256 _minimumSignatures,
        address[] memory _signers
    ) external initializer {
        __Ownable_init(msg.sender);
        __MultiSignatureUpgradeable_init(_minimumSignatures, _signers);
    }
}
