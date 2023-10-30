// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

contract DUSDStaking is
    OwnableUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    string private constant SIGNING_DOMAIN = "DUSD_STAKING";
    string private constant SIGNATURE_VERSION = "1";

    /**
     * @dev Withdraw message structure with signature
     * @param user reward owner
     * @param amount reward amount
     * @param salt to make unique signatures
     * @param signature EIP712 secp256k1 signature
     */
    struct WithdrawMessage {
        address user;
        uint256 amount;
        uint256 salt;
        bytes signature;
    }

    /**
     * @notice Info for update user investment
     * @param user: user address
     * @param amount: investment amount
     */
    struct InvestmentInfo {
        address user;
        uint256 amount;
    }

    IERC20Upgradeable public token;
    address public adminAddress;
    address public botAddress;
    address private serviceSigner;

    mapping(bytes => bool) private signatureUsed;
    mapping(address => uint256) public userDeposit;
    mapping(address => uint256) public userInvestment;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetBotAddress(address indexed _address);
    event SetServiceSignerAddress(address indexed _address);
    event Deposit(address indexed _address, uint256 amount);
    event UpdateInvestment(address indexed _address, uint256 amount);
    event Withdraw(address indexed _address, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "DUSDStaking: only admin");
        _;
    }

    modifier onlyBot() {
        require(msg.sender == botAddress, "DUSDStaking: only bot");
        _;
    }

    function initialize(
        address _tokenAddress,
        address _botAddress,
        address _serviceSigner
    ) external initializer {
        adminAddress = msg.sender;
        token = IERC20Upgradeable(_tokenAddress);
        botAddress = _botAddress;
        serviceSigner = _serviceSigner;

        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __EIP712_init(SIGNING_DOMAIN, SIGNATURE_VERSION);

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

    function setServiceSigner(address _address) external onlyAdmin {
        serviceSigner = _address;

        emit SetServiceSignerAddress(_address);
    }

    /**
     * @notice Function to deposit dusd tokens
     * @param _amount the amount to deposit
     */
    function deposit(uint256 _amount) external whenNotPaused nonReentrant {
        require(token.balanceOf(msg.sender) >= _amount, "DUSDStaking: invalid amount");

        userDeposit[msg.sender] += _amount;

        token.safeTransferFrom(msg.sender, botAddress, _amount);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(
        WithdrawMessage calldata withdrawMessage
    ) external whenNotPaused nonReentrant {
        address signer = _recover(withdrawMessage);

        require(serviceSigner != address(0), "DUSDStaking: service address not set");
        require(signer == serviceSigner, "DUSDStaking: unknown signer");
        require(!signatureUsed[withdrawMessage.signature], "DUSDStaking: already withdrawn");
        require(msg.sender == withdrawMessage.user, "DUSDStaking: wrong caller");

        signatureUsed[withdrawMessage.signature] = true;
        userInvestment[withdrawMessage.user] -= withdrawMessage.amount;

        token.safeTransfer(withdrawMessage.user, withdrawMessage.amount);

        emit Withdraw(withdrawMessage.user, withdrawMessage.amount);
    }

    /**
     * @notice Function to update users investments
     * @param _investmentsInfo InvestmentInfo
     */
    function updateInvestment(InvestmentInfo[] memory _investmentsInfo) external onlyBot {
        for (uint256 i = 0; i < _investmentsInfo.length; ++i) {
            if (userDeposit[_investmentsInfo[i].user] > 0) {
                uint256 investmentDeposit = userDeposit[_investmentsInfo[i].user] -
                    (_investmentsInfo[i].amount - userInvestment[_investmentsInfo[i].user]);
                if (investmentDeposit > 0) {
                    userDeposit[_investmentsInfo[i].user] -= investmentDeposit;
                } else {
                    userDeposit[_investmentsInfo[i].user] = 0;
                }
            }
            userInvestment[_investmentsInfo[i].user] = _investmentsInfo[i].amount;

            emit UpdateInvestment(_investmentsInfo[i].user, _investmentsInfo[i].amount);
        }
    }

    /**
     * @dev Hash EIP712 typed data with keccak
     */
    function _hash(WithdrawMessage calldata withdrawMessage) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("WithdrawMessage(address user,uint256 amount,uint256 salt)"),
                        withdrawMessage.user,
                        withdrawMessage.amount,
                        withdrawMessage.salt
                    )
                )
            );
    }

    function _recover(WithdrawMessage calldata withdrawMessage) private view returns (address) {
        bytes32 digest = _hash(withdrawMessage);

        return ECDSAUpgradeable.recover(digest, withdrawMessage.signature);
    }
}
