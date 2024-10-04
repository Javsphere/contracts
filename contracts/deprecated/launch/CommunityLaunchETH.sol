// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../base/BaseUpgradable.sol";

contract CommunityLaunchETH is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    bool public isSaleActive;
    address public usdtAddress;

    uint256 public availableTokens;
    uint256 public tokensPerTrx;

    /* ========== EVENTS ========== */
    event SetUSDTAddress(address indexed _address);
    event SetSaleActive(bool indexed activeSale);
    event SetAvailableTokens(uint256 indexed availableTokens);
    event TokensPurchased(
        address indexed _address,
        address indexed _referrer,
        uint256 usdAmount,
        bool isBonus
    );
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event SetTokensPerTrx(uint256 indexed tokensPerTrx);

    modifier onlyActive() {
        require(isSaleActive, "CommunityLaunch: contract is not available right now");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _usdtAddress, uint256 _availableTokens) external initializer {
        usdtAddress = _usdtAddress;

        isSaleActive = false;
        availableTokens = _availableTokens;

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setUSDTAddress(address _address) external onlyAdmin {
        usdtAddress = _address;

        emit SetUSDTAddress(_address);
    }

    function setSaleActive(bool _status) external onlyAdmin {
        isSaleActive = _status;

        emit SetSaleActive(_status);
    }

    function setAvailableTokens(uint256 _availableTokens) external onlyAdmin {
        availableTokens = _availableTokens;

        emit SetAvailableTokens(_availableTokens);
    }

    function setTokensPerTrx(uint256 _tokensPerTrx) external onlyAdmin {
        tokensPerTrx = _tokensPerTrx;

        emit SetTokensPerTrx(_tokensPerTrx);
    }

    /**
     * @notice Functon to buy JAV tokens with native tokens
     */
    function buy(
        address _referrer,
        uint256 _amountIn,
        bool _isBonus
    ) external onlyActive nonReentrant {
        require(_amountIn <= tokensPerTrx, "CommunityLaunch: Invalid tokens amount - max amount");
        require(_amountIn <= availableTokens, "CommunityLaunch: Invalid amount for purchase");

        require(
            IERC20(usdtAddress).balanceOf(msg.sender) >= _amountIn,
            "CommunityLaunch: invalid amount"
        );
        IERC20(usdtAddress).safeTransferFrom(msg.sender, address(this), _amountIn);
        availableTokens -= _amountIn;

        emit TokensPurchased(msg.sender, _referrer, _amountIn, _isBonus);
    }

    /**
     * @notice Functon to withdraw amount
     * @param _token token address
     * @param _to recipient address
     * @param _amount amount
     */
    function withdraw(address _token, address _to, uint256 _amount) external onlyAdmin {
        require(
            IERC20(_token).balanceOf(address(this)) >= _amount,
            "CommunityLaunch: Invalid amount"
        );
        IERC20(_token).safeTransfer(_to, _amount);

        emit Withdraw(_token, _to, _amount);
    }
}
