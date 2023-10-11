// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CommunityLaunch is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;
    address public adminAddress;

    bool public isSaleActive;

    uint256 public javPrice; // price in native tokens. E.g

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetSaleActive(bool indexed activeSale);
    event SetJavPrice(uint256 indexed price);
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

    function initialize(address _tokenAddress, uint256 _javPrice) external initializer {
        adminAddress = msg.sender;
        token = IERC20Upgradeable(_tokenAddress);
        isSaleActive = false;
        javPrice = _javPrice;

        __Ownable_init();

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

    function setJavPrice(uint256 _price) external onlyAdmin {
        javPrice = _price;

        emit SetJavPrice(_price);
    }

    /**
     * @notice Functon to buy JAV tokens with native tokens
     */
    function buy() external payable onlyActive {
        uint256 _amount = msg.value / javPrice;
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
    function withdraw(address _token, uint256 _amount) external onlyAdmin {
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }
}
