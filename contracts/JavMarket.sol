// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./base/BaseUpgradable.sol";

contract JavMarket is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

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
    event SetBotAddress(address indexed _address);
    event Buy(address indexed _address, uint256 amount, uint256 tokenId);
    event AddToken(address indexed _address, uint256 tokenId);
    event RemoveToken(uint256 indexed tokenId);
    event TransferAmount(address indexed _address, uint256 amount, uint256 tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenAddress, address _botAddress) external initializer {
        botAddress = _botAddress;
        dusdToken = IERC20(_tokenAddress);

        __Base_init();
        __ReentrancyGuard_init();
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
}
