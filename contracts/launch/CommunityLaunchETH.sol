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

    /* ========== EVENTS ========== */
    event SetUSDTAddress(address indexed _address);
    event SetPairAddress(address indexed _address);
    event SetSaleActive(bool indexed activeSale);
    event SetAvailableTokens(uint256 indexed availableTokens);
    event TokensPurchased(address indexed _address, address indexed _referrer, uint256 usdAmount);
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
        uint256 _availableTokens
    ) external initializer {
        usdtAddress = _usdtAddress;
        pairAddress = _pairAddress;

        isSaleActive = false;
        availableTokens = _availableTokens;

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

    function setAvailableTokens(uint256 _availableTokens) external onlyAdmin {
        availableTokens = _availableTokens;

        emit SetAvailableTokens(_availableTokens);
    }

    /**
     * @notice Functon to buy JAV tokens with native tokens
     */
    function buy(address _referrer, uint256 _amountIn) external payable onlyActive nonReentrant {
        require(availableTokens > 0, "CommunityLaunch: Invalid amount for purchase");
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

        emit TokensPurchased(msg.sender, _referrer, usdAmount);
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

    function _getTokenPrice(uint256 _amount) private view returns (uint256) {
        (uint reserve0, uint reserve1, ) = IVanillaPair(pairAddress).getReserves();
        if (IVanillaPair(pairAddress).token0() == usdtAddress) {
            return (_amount * reserve0) / reserve1;
        } else {
            return (_amount * reserve1) / reserve0;
        }
    }
}
