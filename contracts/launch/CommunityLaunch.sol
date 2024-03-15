// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStateRelayer.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IVanillaPair.sol";
import "../base/BaseUpgradable.sol";

contract CommunityLaunch is BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct VestingParams {
        // start time of the vesting period
        uint128 start;
        // duration in seconds of the cliff in which tokens will begin to vest
        uint128 cliff;
        // duration in seconds of the period in which the tokens will vest
        uint128 duration;
        // duration of a slice period for the vesting in seconds
        uint128 slicePeriodSeconds;
    }

    VestingParams public vestingParams;
    IERC20 public token;
    bool public isSaleActive;
    address public botAddress;
    address public vestingAddress;
    address public freezerAddress;
    address public usdtAddress;
    address public pairAddress;
    address public stateRelayer;

    uint256 public startTokenPrice; // price in usd. E.g
    uint256 public startBlock;
    uint256 public incPricePerBlock;

    /* ========== EVENTS ========== */
    event SetVestingAddress(address indexed _address);
    event SetStateRelayer(address indexed _address);
    event SetBotAddress(address indexed _address);
    event SetUSDTAddress(address indexed _address);
    event SetPairAddress(address indexed _address);
    event SetFreezerAddress(address indexed _address);
    event SetVestingParams(
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds
    );
    event SetSaleActive(bool indexed activeSale);
    event SetStartTokenPrice(uint256 indexed startBlock);
    event SetStartBlock(uint256 indexed price);
    event SetIncPricePerBlock(uint256 indexed incPricePerBlock);
    event TokensPurchased(address indexed _address, address indexed _referrer, uint256 amount);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event WithdrawDFI(address indexed to, uint256 amount);

    modifier onlyActive() {
        require(isSaleActive, "CommunityLaunch: contract is not available right now");
        _;
    }

    modifier onlyBot() {
        require(msg.sender == botAddress, "CommunityLaunch: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _stateRelayer,
        address _botAddress,
        address _usdtAddress,
        address _pairAddress,
        address _vesting,
        address _freezer,
        uint256 _startTokenPrice,
        uint256 _incPricePerBlock,
        VestingParams memory _vestingParams
    ) external initializer {
        token = IERC20(_tokenAddress);
        botAddress = _botAddress;
        stateRelayer = _stateRelayer;
        vestingAddress = _vesting;
        usdtAddress = _usdtAddress;
        pairAddress = _pairAddress;
        freezerAddress = _freezer;

        isSaleActive = false;
        startTokenPrice = _startTokenPrice;
        incPricePerBlock = _incPricePerBlock;
        vestingParams = _vestingParams;

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setVestingParams(VestingParams memory _vestingParams) external onlyAdmin {
        vestingParams = _vestingParams;

        emit SetVestingParams(
            _vestingParams.start,
            _vestingParams.cliff,
            _vestingParams.duration,
            _vestingParams.slicePeriodSeconds
        );
    }

    function setBotAddress(address _address) external onlyAdmin {
        botAddress = _address;

        emit SetBotAddress(_address);
    }

    function setStateRelayer(address _address) external onlyAdmin {
        stateRelayer = _address;

        emit SetStateRelayer(_address);
    }

    function setVestingAddress(address _address) external onlyAdmin {
        vestingAddress = _address;

        emit SetVestingAddress(_address);
    }

    function setUSDTAddress(address _address) external onlyAdmin {
        usdtAddress = _address;

        emit SetUSDTAddress(_address);
    }

    function setPairAddress(address _address) external onlyAdmin {
        pairAddress = _address;

        emit SetPairAddress(_address);
    }

    function setFreezerAddress(address _address) external onlyAdmin {
        freezerAddress = _address;

        emit SetFreezerAddress(_address);
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
     * @notice Functon to buy JAV tokens with native tokens/dusd
     * @param _referrer _referrer address
     * @param _amountIn dusd amount
     * @param _isEqualUSD is 1 dusd = 1 $
     */
    function buy(
        address _referrer,
        uint256 _amountIn,
        bool _isEqualUSD
    ) external payable onlyActive nonReentrant {
        require(block.number >= startBlock, "CommunityLaunch: Need wait startBlock");
        require(
            _amountIn == 0 || msg.value == 0,
            "CommunityLaunch: Cannot pass both DFI and ERC-20 assets"
        );

        uint256 usdAmount = 0;
        uint128 cliff = vestingParams.cliff;
        uint128 duration = vestingParams.duration;
        uint128 slicePeriodSeconds = vestingParams.slicePeriodSeconds;

        if (_amountIn != 0) {
            require(
                IERC20(usdtAddress).balanceOf(msg.sender) >= _amountIn,
                "CommunityLaunch: invalid amount"
            );
            IERC20(usdtAddress).safeTransferFrom(msg.sender, address(this), _amountIn);
            if (_isEqualUSD) {
                usdAmount = _amountIn;
                cliff = cliff * 2;
                duration = duration * 2;
                slicePeriodSeconds = slicePeriodSeconds * 2;
            } else {
                usdAmount = _getDUSDPrice(_amountIn);
            }
        } else {
            uint256 _dusdAmount = _getTokenPrice(msg.value);
            usdAmount = _getDUSDPrice(_dusdAmount);
        }

        uint256 _tokensAmount = (usdAmount * 1e18) / _tokenPrice();
        require(
            token.balanceOf(address(this)) >= _tokensAmount,
            "CommunityLaunch: Invalid amount for purchase"
        );

        _createVesting(
            msg.sender,
            uint128(_tokensAmount),
            vestingParams.start,
            cliff,
            duration,
            slicePeriodSeconds
        );

        emit TokensPurchased(msg.sender, _referrer, _tokensAmount);
    }

    function simulateBuy(
        address _beneficiary,
        address _referrer,
        uint128 _amount,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds
    ) external onlyActive onlyBot {
        require(
            token.balanceOf(address(this)) >= _amount,
            "CommunityLaunch: Invalid amount for purchase"
        );
        _createVesting(_beneficiary, _amount, _start, _cliff, _duration, _slicePeriodSeconds);

        emit TokensPurchased(_beneficiary, _referrer, _amount);
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
     * @notice Functon to withdraw amount dfi
     * @param _to recipient address
     * @param _amount amount
     */
    function withdrawDFI(address payable _to, uint256 _amount) external onlyAdmin {
        require(address(this).balance >= _amount, "CommunityLaunch: Invalid amount");

        _to.transfer(_amount);

        emit WithdrawDFI(_to, _amount);
    }

    function _tokenPrice() private view returns (uint256) {
        if (block.number < startBlock) {
            return startTokenPrice;
        }
        return ((block.number - startBlock) * incPricePerBlock) + startTokenPrice;
    }

    function _createVesting(
        address _beneficiary,
        uint128 _amount,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds
    ) private {
        token.safeTransfer(freezerAddress, _amount);
        ITokenVesting(vestingAddress).createVestingSchedule(
            _beneficiary,
            _start,
            _cliff,
            _duration,
            _slicePeriodSeconds,
            true,
            _amount
        );
    }

    function _getTokenPrice(uint256 _amount) private view returns (uint256) {
        (uint reserve0, uint reserve1,) = IVanillaPair(pairAddress).getReserves();
        if (IVanillaPair(pairAddress).token0() == usdtAddress) {
            return (_amount * reserve0) / reserve1;
        } else {
            return (_amount * reserve1) / reserve0;
        }
    }

    function _getDUSDPrice(uint256 _amount) private view returns (uint256) {
        (, IStateRelayer.DEXInfo memory dex) = IStateRelayer(stateRelayer).getDexPairInfo(
            "DUSD-DFI"
        );
        return (_amount * 1e18) / dex.primaryTokenPrice;
    }
}
