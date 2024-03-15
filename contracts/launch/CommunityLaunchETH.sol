// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IVanillaPair.sol";
import "../base/BaseUpgradable.sol";

contract CommunityLaunchETH is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    bool public isSaleActive;
    address public usdtAddress;
    address public pairAddress;

    uint256 public availableTokens; // availableTokens * 1e18
    uint256 public startTokenPrice; // price in usd. E.g
    uint256 public startBlock;
    uint256 public incPricePerBlock;

    /* ========== EVENTS ========== */
    event SetUSDTAddress(address indexed _address);
    event SetPairAddress(address indexed _address);
    event SetSaleActive(bool indexed activeSale);
    event SetStartTokenPrice(uint256 indexed startBlock);
    event SetStartBlock(uint256 indexed price);
    event SetAvailableTokens(uint256 indexed availableTokens);
    event SetIncPricePerBlock(uint256 indexed incPricePerBlock);
    event TokensPurchased(address indexed _address, address indexed _referrer, uint256 amount);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event WithdrawEth(address indexed to, uint256 amount);

    modifier onlyActive() {
        require(isSaleActive, "CommunityLaunch: contract is not available right now");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdtAddress,
        address _pairAddress,
        uint256 _availableTokens,
        uint256 _startTokenPrice,
        uint256 _incPricePerBlock
    ) external initializer {
        usdtAddress = _usdtAddress;
        pairAddress = _pairAddress;

        isSaleActive = false;
        availableTokens = _availableTokens;
        startTokenPrice = _startTokenPrice;
        incPricePerBlock = _incPricePerBlock;

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setUSDTAddress(address _address) external onlyAdmin {
        usdtAddress = _address;

        emit SetUSDTAddress(_address);
    }

    function setPairAddress(address _address) external onlyAdmin {
        pairAddress = _address;

        emit SetPairAddress(_address);
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

    function setAvailableTokens(uint256 _availableTokens) external onlyAdmin {
        availableTokens = _availableTokens;

        emit SetAvailableTokens(_availableTokens);
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
        return availableTokens;
    }

    /**
     * @notice Functon to buy JAV tokens with native tokens
     */
    function buy(address _referrer, uint256 _amountIn) external payable onlyActive nonReentrant {
        require(block.number >= startBlock, "CommunityLaunch: Need wait startBlock");
        require(
            _amountIn == 0 || msg.value == 0,
            "CommunityLaunch: Cannot pass both DFI and ERC-20 assets"
        );

        uint256 usdAmount = 0;

        if (_amountIn != 0) {
            require(
                IERC20(usdtAddress).balanceOf(msg.sender) >= _amountIn,
                "CommunityLaunch: invalid amount"
            );
            IERC20(usdtAddress).safeTransferFrom(msg.sender, address(this), _amountIn);
            usdAmount = _amountIn;
        } else {
            usdAmount = _getTokenPrice(msg.value);
        }

        uint256 _tokensAmount = (usdAmount * 1e18) / _tokenPrice();
        require(availableTokens >= _tokensAmount, "CommunityLaunch: Invalid amount for purchase");

        availableTokens -= _tokensAmount;

        emit TokensPurchased(msg.sender, _referrer, _tokensAmount);
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

    /**
     * @notice Functon to withdraw amount eth
     * @param _to recipient address
     * @param _amount amount
     */
    function withdrawEth(address payable _to, uint256 _amount) external onlyAdmin {
        require(address(this).balance >= _amount, "CommunityLaunch: Invalid amount");

        _to.transfer(_amount);

        emit WithdrawEth(_to, _amount);
    }

    function _tokenPrice() private view returns (uint256) {
        if (block.number < startBlock) {
            return startTokenPrice;
        }
        return ((block.number - startBlock) * incPricePerBlock) + startTokenPrice;
    }

    function _getTokenPrice(uint256 _amount) private view returns (uint256) {
        (uint reserve0, uint reserve1, ) = IVanillaPair(pairAddress).getReserves();
        if (IVanillaPair(pairAddress).token0() == usdtAddress) {
            return (_amount * reserve0) / reserve1;
        } else {
            return (_amount * reserve1) / reserve0;
        }
    }
}
