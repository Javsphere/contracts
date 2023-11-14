// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC20Extended.sol";

contract DFIStaking is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20Extended;

    /**
     * @notice Info for update user investment/withdraw info
     * @param user: user address
     * @param amount: investment amount
     */
    struct UserAmountInfo {
        address user;
        uint256 amount;
    }

    IERC20Extended public token;
    address public adminAddress;
    address public botAddress;
    uint256 public minimumDepositAmount;

    mapping(address => uint256) public userDeposit;
    mapping(address => uint256) public userInvestment;
    mapping(address => uint256) public userRequestedWithdraw;
    mapping(address => uint256) public userClaimableAmount;
    mapping(address => uint256) public userMintRewards;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetTokenAddress(address indexed _address);
    event SetBotAddress(address indexed _address);
    event SetMinimumDepositAmount(uint256 indexed _amount);
    event Deposit(address indexed _address, uint256 amount);
    event UpdateInvestmentByDeposit(address indexed _address, uint256 amount);
    event UpdateInvestmentByRewards(address indexed _address, uint256 amount);
    event UpdateClaimableAmount(address indexed _address, uint256 amount);
    event RequestWithdraw(address indexed _address, uint256 amount);
    event Withdraw(address indexed _address, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "DFIStaking: only admin");
        _;
    }

    modifier onlyBot() {
        require(msg.sender == botAddress, "DFIStaking: only bot");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _botAddress,
        uint256 _minimumDepositAmount
    ) external initializer {
        adminAddress = msg.sender;
        token = IERC20Extended(_tokenAddress);
        botAddress = _botAddress;
        minimumDepositAmount = _minimumDepositAmount;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
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

    function setTokenAddress(address _address) external onlyAdmin {
        token = IERC20Extended(_address);

        emit SetTokenAddress(_address);
    }

    function setMinimumDepositAmount(uint256 _amount) external onlyAdmin {
        minimumDepositAmount = _amount;

        emit SetMinimumDepositAmount(_amount);
    }

    /**
     * @notice Function to deposit dusd tokens
     */
    function deposit() external payable whenNotPaused nonReentrant {
        require(msg.value >= minimumDepositAmount, "DFIStaking: invalid deposit amount");
        payable(botAddress).transfer(msg.value);
        userDeposit[msg.sender] += msg.value;

        token.mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    function requestWithdraw(uint256 _amount) external whenNotPaused nonReentrant {
        require(
            userInvestment[msg.sender] >= _amount + userRequestedWithdraw[msg.sender],
            "DFIStaking: invalid amount for withdraw"
        );
        userRequestedWithdraw[msg.sender] += _amount;

        emit RequestWithdraw(msg.sender, _amount);
    }

    function withdraw() external whenNotPaused nonReentrant {
        uint256 _amount = userClaimableAmount[msg.sender];
        require(_amount > 0, "DFIStaking: invalid withdraw amount");
        require(address(this).balance >= _amount, "DFIStaking: not enough tokens");
        token.burnFrom(msg.sender, _amount);

        userClaimableAmount[msg.sender] = 0;

        payable(msg.sender).transfer(_amount);

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
                "DFIStaking: invalid deposit info"
            );
            userInvestment[_depositInfo[i].user] += _depositInfo[i].amount;
            userDeposit[_depositInfo[i].user] -= _depositInfo[i].amount;

            emit UpdateInvestmentByDeposit(_depositInfo[i].user, _depositInfo[i].amount);
        }
        for (uint256 i = 0; i < _rewardsInfo.length; ++i) {
            userInvestment[_rewardsInfo[i].user] += _rewardsInfo[i].amount;

            if (
                userMintRewards[_rewardsInfo[i].user] + _rewardsInfo[i].amount >
                minimumDepositAmount
            ) {
                token.mint(
                    _rewardsInfo[i].user,
                    userMintRewards[_rewardsInfo[i].user] + _rewardsInfo[i].amount
                );
            } else {
                userMintRewards[_rewardsInfo[i].user] += _rewardsInfo[i].amount;
            }

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
                "DFIStaking: invalid claimable amount"
            );
            userRequestedWithdraw[_withdrawInfo[i].user] -= _withdrawInfo[i].amount;
            userClaimableAmount[_withdrawInfo[i].user] += _withdrawInfo[i].amount;
            userInvestment[_withdrawInfo[i].user] -= _withdrawInfo[i].amount;

            emit UpdateClaimableAmount(_withdrawInfo[i].user, _withdrawInfo[i].amount);
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[41] private ____gap;
}
