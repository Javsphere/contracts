// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./base/BaseUpgradable.sol";

contract DUSDStaking is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @notice Info for update user investment/withdraw info
     * @param user: user address
     * @param amount: investment amount
     */
    struct UserAmountInfo {
        address user;
        uint256 amount;
    }

    IERC20 public token;
    address public botAddress;

    mapping(address => uint256) public userDeposit;
    mapping(address => uint256) public userInvestment;
    mapping(address => uint256) public userRequestedWithdraw;
    mapping(address => uint256) public userClaimableAmount;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event Deposit(address indexed _address, uint256 amount);
    event UpdateInvestmentByDeposit(address indexed _address, uint256 amount);
    event UpdateInvestmentByRewards(address indexed _address, uint256 amount);
    event UpdateClaimableAmount(address indexed _address, uint256 amount);
    event RequestWithdraw(address indexed _address, uint256 amount);
    event Withdraw(address indexed _address, uint256 amount);

    modifier onlyBot() {
        require(msg.sender == botAddress, "DUSDStaking: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenAddress, address _botAddress) external initializer {
        token = IERC20(_tokenAddress);
        botAddress = _botAddress;

        __Base_init();
        __ReentrancyGuard_init();

        emit Initialized(msg.sender, block.number);
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
