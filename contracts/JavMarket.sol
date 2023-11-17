// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract JavMarket is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    address public adminAddress;
    IERC20 public dusdToken;
    address public botAddress;
    uint256 public currentTokenId;
    uint256 public totalOrders;

    mapping(uint256 => address) public tokens;
    mapping(uint256 => uint256) public tokenFee;
    mapping(uint256 => bool) public isActiveToken;
    mapping(uint256 => uint256) public totalAmountByToken;
    mapping(uint256 => uint256) public totalOrdersByToken;
    mapping(address => uint256) public userClaimableAmount;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetBotAddress(address indexed _address);
    event Buy(address indexed _address, uint256 amount, uint256 tokenId);
    event AddToken(address indexed _address, uint256 tokenId);
    event RemoveToken(uint256 indexed tokenId);
    event TransferAmount(address indexed _address, uint256 amount, uint256 tokenId);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "JavMarket: only admin");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenAddress, address _botAddress) external initializer {
        adminAddress = msg.sender;
        botAddress = _botAddress;
        dusdToken = IERC20(_tokenAddress);

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

    function addToken(address _address) external onlyAdmin {
        currentTokenId++;
        tokens[currentTokenId] = _address;
        isActiveToken[currentTokenId] = true;

        emit AddToken(_address, currentTokenId);
    }

    function removeToken(uint256 _tokenId) external onlyAdmin {
        isActiveToken[_tokenId] = false;

        emit RemoveToken(_tokenId);
    }

    function buy(uint256 _amount, uint256 _tokenId) external whenNotPaused nonReentrant {
        require(isActiveToken[_tokenId], "JavMarket: token not active");
        require(dusdToken.balanceOf(msg.sender) >= _amount, "JavMarket: invalid amount");

        totalAmountByToken[_tokenId] += _amount;
        totalOrdersByToken[_tokenId] += 1;
        totalOrders++;

        dusdToken.safeTransferFrom(msg.sender, botAddress, _amount);

        emit Buy(msg.sender, _amount, _tokenId);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[39] private ____gap;
}
