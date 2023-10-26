// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./access/MultiSignatureUpgradeable.sol";

contract CommunityLaunch is
    OwnableUpgradeable,
    MultiSignatureUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant WITHDRAW = keccak256("WITHDRAW");

    IERC20Upgradeable public token;
    address public adminAddress;

    bool public isSaleActive;

    uint256 public startTokenPrice; // price in native tokens. E.g
    uint256 public startBlock;
    uint256 public incPricePerBlock;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetSaleActive(bool indexed activeSale);
    event SetStartTokenPrice(uint256 indexed startBlock);
    event SetStartBlock(uint256 indexed price);
    event SetIncPricePerBlock(uint256 indexed incPricePerBlock);
    event TokensPurchased(address indexed _address, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "CommunityLaunch: only admin");
        _;
    }

    modifier onlyActive() {
        require(isSaleActive, "CommunityLaunch: contract is not available right now");
        _;
    }

    function initialize(
        address _tokenAddress,
        uint256 _startTokenPrice,
        uint256 _incPricePerBlock,
        uint256 _minimumSignatures,
        address[] memory _signers
    ) external initializer {
        adminAddress = msg.sender;
        token = IERC20Upgradeable(_tokenAddress);
        isSaleActive = false;
        startTokenPrice = _startTokenPrice;
        incPricePerBlock = _incPricePerBlock;

        __Ownable_init();
        __ReentrancyGuard_init();
        __MultiSignatureUpgradeable_init(_minimumSignatures, _signers);

        emit Initialized(msg.sender, block.number);
    }

    function setAdminAddress(address _address) external onlyAdmin {
        adminAddress = _address;

        emit SetAdminAddress(_address);
    }

    function setSaleActive(bool _status) external onlyAdmin {
        isSaleActive = _status;

        emit SetSaleActive(_status);
    }

    function setStartTokenPrice(uint256 _price) external onlyAdmin {
        startTokenPrice = _price;

        emit SetStartTokenPrice(_price);
    }

    function setStartBlock(uint256 _startBlock) external onlyAdmin {
        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    function setIncPricePerBlock(uint256 _incPricePerBlock) external onlyAdmin {
        incPricePerBlock = _incPricePerBlock;

        emit SetIncPricePerBlock(_incPricePerBlock);
    }

    /**
     * @notice Functon to get current token price
     */
    function tokenPrice() external view returns (uint256) {
        return _tokenPrice();
    }

    /**
     * @notice Functon to get tokens balance
     */
    function tokensBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Functon to buy JAV tokens with native tokens
     */
    function buy() external payable onlyActive nonReentrant {
        require(block.number >= startBlock, "CommunityLaunch: Need wait startBlock");
        uint256 _amount = msg.value / _tokenPrice();
        require(
            token.balanceOf(address(this)) >= _amount,
            "CommunityLaunch: Invalid amount for purchase"
        );

        token.safeTransfer(msg.sender, _amount);

        emit TokensPurchased(msg.sender, _amount);
    }

    /**
     * @notice Functon to withdraw amount
     * @param _token token address
     * @param _amount amount
     */
    function withdraw(address _token, uint256 _amount) external onlyAdmin needAction(WITHDRAW) {
        require(
            IERC20Upgradeable(_token).balanceOf(address(this)) >= _amount,
            "CommunityLaunch: Invalid amount"
        );
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function _tokenPrice() private view returns (uint256) {
        if (block.number < startBlock) {
            return startTokenPrice;
        }
        return ((block.number - startBlock) * incPricePerBlock) + startTokenPrice;
    }
}
