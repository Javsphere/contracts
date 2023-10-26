// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./access/MultiSignatureUpgradeable.sol";
import "./DutchAuction.sol";

contract DutchAuctionFactory is OwnableUpgradeable, MultiSignatureUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant DEPLOY = keccak256("DEPLOY");

    address public adminAddress;
    address public tokenAddress;

    EnumerableSet.AddressSet private _auctions;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event SetTokenAddress(address indexed _address);
    event Deploy(address indexed _address);

    modifier onlyAdmin() {
        require(
            msg.sender == adminAddress || msg.sender == owner(),
            "DutchAuctionFactory: only admin"
        );
        _;
    }

    function initialize(
        address _tokenAddress,
        uint256 _minimumSignatures,
        address[] memory _signers
    ) external initializer {
        adminAddress = msg.sender;
        tokenAddress = _tokenAddress;

        __Ownable_init();
        __MultiSignatureUpgradeable_init(_minimumSignatures, _signers);

        emit Initialized(msg.sender, block.number);
    }

    function setAdminAddress(address _address) external onlyAdmin {
        adminAddress = _address;

        emit SetAdminAddress(_address);
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
    ) external onlyAdmin needAction(DEPLOY) {
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
