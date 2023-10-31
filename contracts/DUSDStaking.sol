// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DUSDStaking is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @notice Info for update user investment/withdraw info
     * @param user: user address
     * @param amount: investment amount
     */
    struct UserAmountInfo {
        address user;
        uint256 amount;
    }

    IERC20Upgradeable public token;
    address public adminAddress;
    address public botAddress;

    mapping(address => uint256) public userDeposit;
    mapping(address => uint256) public userInvestment;
    mapping(address => uint256) public userRequestedWithdraw;
    mapping(address => uint256) public userClaimableAmount;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetBotAddress(address indexed _address);
    event Deposit(address indexed _address, uint256 amount);
    event UpdateInvestment(address indexed _address, uint256 amount);
    event UpdateClaimableAmount(address indexed _address, uint256 amount);
    event RequestWithdraw(address indexed _address, uint256 amount);
    event Withdraw(address indexed _address, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "DUSDStaking: only admin");
        _;
    }

    modifier onlyBot() {
        require(msg.sender == botAddress, "DUSDStaking: only bot");
        _;
    }

    function initialize(address _tokenAddress, address _botAddress) external initializer {
        adminAddress = msg.sender;
        token = IERC20Upgradeable(_tokenAddress);
        botAddress = _botAddress;

        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

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

    function requestWithdraw(uint256 _amount) external whenNotPaused nonReentrant {
        require(
            userInvestment[msg.sender] >= _amount + userRequestedWithdraw[msg.sender],
            "DUSDStaking: invalid amount"
        );
        userRequestedWithdraw[msg.sender] += _amount;

        emit RequestWithdraw(msg.sender, _amount);
    }

    function withdraw() external whenNotPaused nonReentrant {
        uint256 _amount = userClaimableAmount[msg.sender];
        require(_amount > 0, "DUSDStaking: invalid amount");
        userClaimableAmount[msg.sender] = 0;

        token.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Function to update users investments
     * @param _investmentsInfo UserAmountInfo
     */
    function updateInvestment(UserAmountInfo[] memory _investmentsInfo) external onlyBot {
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
     * @notice Function to update users claimable amount
     * @param _withdrawInfo UserAmountInfo
     */
    function updateWithdraw(UserAmountInfo[] memory _withdrawInfo) external onlyBot {
        uint256 _transferAmount;
        for (uint256 i = 0; i < _withdrawInfo.length; ++i) {
            userRequestedWithdraw[_withdrawInfo[i].user] -= _withdrawInfo[i].amount;
            userClaimableAmount[_withdrawInfo[i].user] += _withdrawInfo[i].amount;
            userInvestment[_withdrawInfo[i].user] -= _withdrawInfo[i].amount;

            _transferAmount += _withdrawInfo[i].amount;

            emit UpdateClaimableAmount(_withdrawInfo[i].user, _withdrawInfo[i].amount);
        }

        token.safeTransferFrom(botAddress, address(this), _transferAmount);
    }
}
