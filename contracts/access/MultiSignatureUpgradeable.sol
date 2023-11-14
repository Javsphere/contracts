// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract MultiSignatureUpgradeable is AccessControlUpgradeable {
    bytes32 public constant GRANT_ROLE = keccak256("GRANT_ROLE");
    bytes32 public constant REVOKE_ROLE = keccak256("REVOKE_ROLE");
    bytes32 public constant INC_MIN_SIGN = keccak256("INC_MIN_SIGN");

    uint256 public minimumSignatures;
    // action -> id
    mapping(bytes32 => uint256) public actionId;
    // action -> actionId -> signatures
    mapping(bytes32 => mapping(uint256 => uint256)) public signatures;
    // address -> action -> actionId -> signatureUsedByAction
    mapping(address => mapping(bytes32 => mapping(uint256 => bool))) public signatureUsedByAction;

    /* ========== EVENTS ========== */
    event SignAction(address indexed executor, bytes32 action);
    event IncreaseMinimumSignatures(uint256 indexed minimumSignatures);

    modifier needAction(bytes32 _action) {
        require(
            signatures[_action][actionId[_action]] >= minimumSignatures,
            "MultiSignatureUpgradeable: need more signatures"
        );
        actionId[_action] += 1;
        _;
    }

    function __MultiSignatureUpgradeable_init(
        uint256 _minimumSignatures,
        address[] memory _signers
    ) internal onlyInitializing {
        minimumSignatures = _minimumSignatures;
        for (uint256 i = 0; i < _signers.length; ++i) {
            _grantRole(0x00, _signers[i]);
        }
        __AccessControl_init();
    }

    /**
     * @notice Sign action
     * @param _action action
     */
    function signAction(bytes32 _action) external onlyRole(0x00) {
        uint256 _actionId = actionId[_action];
        require(
            !signatureUsedByAction[msg.sender][_action][_actionId],
            "MultiSignatureUpgradeable: No signatures left in this wallet."
        );
        signatureUsedByAction[msg.sender][_action][_actionId] = true;
        signatures[_action][_actionId] += 1;

        emit SignAction(msg.sender, _action);
    }

    /**
     * @notice Increase minimum signatures
     */
    function increaseMinimumSignatures() external onlyRole(0x00) needAction(INC_MIN_SIGN) {
        minimumSignatures += 1;

        emit IncreaseMinimumSignatures(minimumSignatures);
    }

    /**
     * @notice Grant role for user
     * @param _role role
     * @param _account user address
     */
    function grantRole(
        bytes32 _role,
        address _account
    ) public virtual override onlyRole(0x00) needAction(GRANT_ROLE) {
        _grantRole(_role, _account);
    }

    /**
     * @notice Revoke role for user
     * @param _role role
     * @param _account user address
     */
    function revokeRole(
        bytes32 _role,
        address _account
    ) public virtual override onlyRole(0x00) needAction(REVOKE_ROLE) {
        _revokeRole(_role, _account);
    }
}
