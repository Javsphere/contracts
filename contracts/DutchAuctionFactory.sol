// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./DutchAuction.sol";
import "./base/BaseUpgradable.sol";

contract DutchAuctionFactory is BaseUpgradable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public multiSignWallet;
    address public tokenAddress;

    EnumerableSet.AddressSet private _auctions;

    /* ========== EVENTS ========== */
    event SetMultiSignWalletAddress(address indexed _address);
    event SetTokenAddress(address indexed _address);
    event Deploy(address indexed _address);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet, "DutchAuctionFactory: only multi sign wallet");
        _;
    }

    function initialize(address _tokenAddress, address _multiSignWallet) external initializer {
        tokenAddress = _tokenAddress;
        multiSignWallet = _multiSignWallet;

        __Base_init();
    }

    function setMultiSignWalletAddress(address _address) external onlyAdmin {
        multiSignWallet = _address;

        emit SetMultiSignWalletAddress(_address);
    }

    function setTokenAddress(address _address) external onlyAdmin {
        tokenAddress = _address;

        emit SetTokenAddress(_address);
    }

    /**
     * @notice Function to deploy DutchAuction
     * @param _startDate: start date of auction
     * @param _endDate: end date of auction
     * @param _startPrice: start price of auction
     * @param _minimumPrice: min price of auction
     */
    function deploy(
        uint256 _startDate,
        uint256 _endDate,
        uint256 _startPrice,
        uint256 _minimumPrice
    ) external onlyMultiSign {
        DutchAuction auction = new DutchAuction();
        auction.initDutchAuction(
            adminAddress,
            tokenAddress,
            _startDate,
            _endDate,
            _startPrice,
            _minimumPrice
        );
        _auctions.add(address(auction));

        emit Deploy(address(auction));
    }

    /**
     * @notice Function to get all auction addresses
     */
    function getAuctions() external view returns (address[] memory) {
        return _auctions.values();
    }

    /**
     * @notice Function to get auction address by index
     * @param index auction index
     */
    function getAuctionAt(uint256 index) external view returns (address) {
        return _auctions.at(index);
    }
}
