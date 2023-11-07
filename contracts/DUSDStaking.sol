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
    event UpdateInvestmentByDeposit(address indexed _address, uint256 amount);
    event UpdateInvestmentByRewards(address indexed _address, uint256 amount);
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
        require(token.balanceOf(msg.sender) >= _amount, "DUSDStaking: invalid amount for deposit");

        userDeposit[msg.sender] += _amount;

        token.safeTransferFrom(msg.sender, botAddress, _amount);

        emit Deposit(msg.sender, _amount);
    }

    function requestWithdraw(uint256 _amount) external whenNotPaused nonReentrant {
        require(
            userInvestment[msg.sender] >= _amount + userRequestedWithdraw[msg.sender],
            "DUSDStaking: invalid amount for withdraw"
        );
        userRequestedWithdraw[msg.sender] += _amount;

        emit RequestWithdraw(msg.sender, _amount);
    }

    function withdraw() external whenNotPaused nonReentrant {
        uint256 _amount = userClaimableAmount[msg.sender];
        require(_amount > 0, "DUSDStaking: invalid withdraw amount");
        require(token.balanceOf(address(this)) >= _amount, "DUSDStaking: not enough tokens");
        userClaimableAmount[msg.sender] = 0;

        token.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Function to update users investments
     * @param _depositInfo UserDepositInfo
     * @param _rewardsInfo UserRewardsInfo
     */
    function updateInvestment(
        UserAmountInfo[] memory _depositInfo,
        UserAmountInfo[] memory _rewardsInfo
    ) external onlyBot {
        for (uint256 i = 0; i < _depositInfo.length; ++i) {
            require(
                userDeposit[_depositInfo[i].user] >= _depositInfo[i].amount,
                "DUSDStaking: invalid deposit info"
            );
            userInvestment[_depositInfo[i].user] += _depositInfo[i].amount;
            userDeposit[_depositInfo[i].user] -= _depositInfo[i].amount;

            emit UpdateInvestmentByDeposit(_depositInfo[i].user, _depositInfo[i].amount);
        }
        for (uint256 i = 0; i < _rewardsInfo.length; ++i) {
            userInvestment[_rewardsInfo[i].user] += _rewardsInfo[i].amount;

            emit UpdateInvestmentByRewards(_rewardsInfo[i].user, _rewardsInfo[i].amount);
        }
    }

    /**
     * @notice Function to update users claimable amount
     * @param _withdrawInfo UserAmountInfo
     */
    function updateWithdraw(UserAmountInfo[] memory _withdrawInfo) external onlyBot {
        for (uint256 i = 0; i < _withdrawInfo.length; ++i) {
            require(
                userRequestedWithdraw[_withdrawInfo[i].user] >= _withdrawInfo[i].amount,
                "DUSDStaking: invalid claimable amount"
            );
            userRequestedWithdraw[_withdrawInfo[i].user] -= _withdrawInfo[i].amount;
            userClaimableAmount[_withdrawInfo[i].user] += _withdrawInfo[i].amount;
            userInvestment[_withdrawInfo[i].user] -= _withdrawInfo[i].amount;

            emit UpdateClaimableAmount(_withdrawInfo[i].user, _withdrawInfo[i].amount);
        }
    }
}
