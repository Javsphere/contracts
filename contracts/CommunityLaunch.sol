// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./base/BaseUpgradable.sol";

contract CommunityLaunch is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    bool public isSaleActive;
    address public multiSignWallet;

    uint256 public startTokenPrice; // price in native tokens. E.g
    uint256 public startBlock;
    uint256 public incPricePerBlock;

    /* ========== EVENTS ========== */
    event SetMultiSignWalletAddress(address indexed _address);
    event SetSaleActive(bool indexed activeSale);
    event SetStartTokenPrice(uint256 indexed startBlock);
    event SetStartBlock(uint256 indexed price);
    event SetIncPricePerBlock(uint256 indexed incPricePerBlock);
    event TokensPurchased(address indexed _address, uint256 amount);
    event Withdraw(address indexed token, address indexed to, uint256 amount);

    modifier onlyActive() {
        require(isSaleActive, "CommunityLaunch: contract is not available right now");
        _;
    }

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet, "CommunityLaunch: only multi sign wallet");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _multiSignWallet,
        uint256 _startTokenPrice,
        uint256 _incPricePerBlock
    ) external initializer {
        token = IERC20(_tokenAddress);
        multiSignWallet = _multiSignWallet;
        isSaleActive = false;
        startTokenPrice = _startTokenPrice;
        incPricePerBlock = _incPricePerBlock;

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setMultiSignWalletAddress(address _address) external onlyAdmin {
        multiSignWallet = _address;

        emit SetMultiSignWalletAddress(_address);
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
     * @param _to recipient address
     * @param _amount amount
     */
    function withdraw(address _token, address _to, uint256 _amount) external onlyMultiSign {
        require(
            IERC20(_token).balanceOf(address(this)) >= _amount,
            "CommunityLaunch: Invalid amount"
        );
        IERC20(_token).safeTransfer(_to, _amount);

        emit Withdraw(_token, _to, _amount);
    }

    function _tokenPrice() private view returns (uint256) {
        if (block.number < startBlock) {
            return startTokenPrice;
        }
        return ((block.number - startBlock) * incPricePerBlock) + startTokenPrice;
    }
}
