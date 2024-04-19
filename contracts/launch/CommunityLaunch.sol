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
        // duration in seconds of the cliff in which tokens will begin to vest
        uint128 cliff;
        // duration in seconds of the period in which the tokens will vest
        uint128 duration;
        // duration of a slice period for the vesting in seconds
        uint128 slicePeriodSeconds;
        // vesting type
        uint8 vestingType;
        // lock id (use only for freezer
        uint8 lockId;
    }

    struct ConfigAddresses {
        address tokenAddress;
        address stateRelayer;
        address botAddress;
        address dusdAddress;
        address usdtAddress;
        address pairAddress;
        address vesting;
        address freezer;
    }

    VestingParams public vestingParams;
    IERC20 public token;
    bool public isSaleActive;
    address public botAddress;
    address public vestingAddress;
    address public freezerAddress;
    address public dusdAddress;
    address public usdtAddress;
    address public pairAddress;
    address public stateRelayer;

    uint256 public startTokenPrice; // price in usd. E.g
    uint256 public endTokenPrice; // price in usd. E.g
    uint256 public tokensToSale;
    uint256 public sectionsNumber;

    mapping(uint256 => uint256) public tokensAmountByType;

    uint256 public avgDUSDPrice;
    uint256 public lastUpdateBlockDUSDPrice;
    mapping(uint256 => uint256[]) public tokenFactor;
    uint256 public maxBagSize;

    /* ========== EVENTS ========== */
    event SetVestingAddress(address indexed _address);
    event SetStateRelayer(address indexed _address);
    event SetBotAddress(address indexed _address);
    event SetDUSDAddress(address indexed _address);
    event SetUSDTAddress(address indexed _address);
    event SetPairAddress(address indexed _address);
    event SetFreezerAddress(address indexed _address);
    event SetVestingParams(
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        uint8 vestingType,
        uint8 lockId
    );
    event SetSaleActive(bool indexed activeSale);
    event SetStartTokenPrice(uint256 indexed startTokenPrice);
    event SetEndTokenPrice(uint256 indexed endTokenPrice);
    event SetTokensToSale(uint256 indexed tokensToSale);
    event SetTokensAmountByType(uint256 indexed tokensAmountByType);
    event SetSectionsNumber(uint256 indexed sectionsNumber);
    event TokensPurchased(
        address indexed _address,
        address indexed _referrer,
        uint256 amount,
        uint256 saleTokenType,
        uint256 inputAmount,
        uint256 price
    );
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event WithdrawDFI(address indexed to, uint256 amount);
    event UpdateDUSDPrice(uint256 indexed lastBlock, uint256 price);
    event SetMaxBagSize(uint256 indexed maxBagSize);
    event SetTokenFactor(uint256 indexed tokenId, uint256[] factor);

    modifier onlyActive() {
        require(isSaleActive, "CommunityLaunch: contract is not available right now");
        _;
    }

    modifier onlyBot() {
        require(msg.sender == botAddress || msg.sender == owner(), "CommunityLaunch: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _tokensToSale,
        uint256 _startTokenPrice,
        uint256 _endTokenPrice,
        uint256 _sectionsNumber,
        uint256[] memory _tokensAmountByType,
        ConfigAddresses memory _configAddresses,
        VestingParams memory _vestingParams
    ) external initializer {
        token = IERC20(_configAddresses.tokenAddress);
        botAddress = _configAddresses.botAddress;
        stateRelayer = _configAddresses.stateRelayer;
        vestingAddress = _configAddresses.vesting;
        dusdAddress = _configAddresses.dusdAddress;
        usdtAddress = _configAddresses.usdtAddress;
        pairAddress = _configAddresses.pairAddress;
        freezerAddress = _configAddresses.freezer;

        isSaleActive = false;
        startTokenPrice = _startTokenPrice;
        endTokenPrice = _endTokenPrice;
        tokensToSale = _tokensToSale;
        sectionsNumber = _sectionsNumber;
        vestingParams = _vestingParams;

        tokensAmountByType[0] = _tokensAmountByType[0];

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setVestingParams(VestingParams memory _vestingParams) external onlyAdmin {
        vestingParams = _vestingParams;

        emit SetVestingParams(
            _vestingParams.cliff,
            _vestingParams.duration,
            _vestingParams.slicePeriodSeconds,
            _vestingParams.vestingType,
            _vestingParams.lockId
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

    function setDUSDAddress(address _address) external onlyAdmin {
        dusdAddress = _address;

        emit SetDUSDAddress(_address);
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

    function setEndTokenPrice(uint256 _price) external onlyAdmin {
        endTokenPrice = _price;

        emit SetEndTokenPrice(_price);
    }

    function setSectionsNumber(uint256 _sectionsNumber) external onlyAdmin {
        sectionsNumber = _sectionsNumber;

        emit SetSectionsNumber(_sectionsNumber);
    }

    function setTokensToSale(uint256 _tokensToSale) external onlyAdmin {
        tokensToSale = _tokensToSale;

        emit SetTokensToSale(_tokensToSale);
    }

    function setTokensAmountByType(uint256[] memory _tokensAmountByType) external onlyAdmin {
        tokensAmountByType[0] = _tokensAmountByType[0];

        emit SetTokensAmountByType(_tokensAmountByType[0]);
    }

    function setMaxBagSize(uint256 _maxBagSize) external onlyAdmin {
        maxBagSize = _maxBagSize;

        emit SetMaxBagSize(_maxBagSize);
    }

    function setTokenFactor(uint256 _tokenId, uint256[] memory _factor) external onlyAdmin {
        require(_factor.length == 2, "CommunityLaunch: invalid factor value");
        tokenFactor[_tokenId] = _factor;

        emit SetTokenFactor(_tokenId, _factor);
    }

    /**
     * @notice Functon to calculate tokens based on usd input amount
     */
    function getTokenAmountByUsd(uint256 _usdAmount) external view returns (uint256) {
        return _calculateTokensAmount(_usdAmount, false);
    }

    /**
     * @notice Functon to get token price
     */
    function getTokenPrice() external view returns (uint256) {
        (uint256 section, , ) = _calculateCurrentSection();

        return _getTokenPrice(section - 1);
    }

    /**
     * @notice Functon to get tokens balance
     */
    function tokensBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Functon to get dfi to usd price
     */
    function getDFIToUSDPrice() external view returns (uint256) {
        return _getTokenToUSDPrice("dUSDT-DFI");
    }

    /**
     * @notice Functon to get dusd to usd price
     */
    function getDUSDToUSDPrice() external view returns (uint256) {
        return _dfiToUSD(_dusdToDFI(1e18));
    }

    function getTokenFactorBonus(uint256 _tokenId) external view returns (uint256) {
        return _calculateFactorBonus(_tokenId, false);
    }

    function updateDUSDPrice() external {
        uint256 newAvgPrice;
        uint256 _price = _getDUSDToDFIPrice(); // 1e18

        if (avgDUSDPrice > 0) {
            uint256 _multiplier = (2 * 1e18) / (block.number - lastUpdateBlockDUSDPrice + 1);
            newAvgPrice = ((_price * _multiplier) + (avgDUSDPrice * (1e18 - _multiplier))) / 1e18;
        } else {
            newAvgPrice = _price;
        }

        avgDUSDPrice = newAvgPrice;
        lastUpdateBlockDUSDPrice = block.number;

        emit UpdateDUSDPrice(lastUpdateBlockDUSDPrice, avgDUSDPrice);
    }

    /**
     * @notice Functon to buy JAV tokens with native tokens/dusd
     * @param _referrer _referrer address
     * @param _amountIn dusd amount
     * @param _token token address
     * @param _isLongerVesting is double vesting period
     */
    function buy(
        address _referrer,
        uint256 _amountIn,
        address _token,
        bool _isLongerVesting
    ) external payable onlyActive nonReentrant {
        require(
            _amountIn == 0 || msg.value == 0,
            "CommunityLaunch: Cannot pass both DFI and ERC-20 assets"
        );

        bool bonus = false;
        uint256 saleTokenType;
        uint256 inputAmount;
        uint256 usdAmount = 0;
        uint128 duration = vestingParams.duration;
        uint256 lockId = vestingParams.lockId;

        if (_amountIn != 0) {
            require(
                _token == usdtAddress || _token == dusdAddress,
                "CommunityLaunch: invalid token"
            );
            require(
                IERC20(_token).balanceOf(msg.sender) >= _amountIn,
                "CommunityLaunch: invalid amount"
            );
            inputAmount = _amountIn;
            IERC20(_token).safeTransferFrom(msg.sender, address(this), inputAmount);

            usdAmount = _token == usdtAddress ? _amountIn : _dfiToUSD(_dusdToDFI(_amountIn));
            saleTokenType = _token == usdtAddress ? 1 : 2;
            bonus = _token == usdtAddress ? true : false;
        } else {
            inputAmount = msg.value;
            usdAmount = _dfiToUSD(inputAmount);
            bonus = true;
            saleTokenType = 0;
        }

        uint256 _tokensAmount = _calculateTokensAmount(usdAmount, false);

        if (_isLongerVesting) {
            duration = duration * 2;
            lockId += 1;
            _tokensAmount = (_tokensAmount * _calculateFactorBonus(saleTokenType, false)) / 100;
        }

        require(_tokensAmount <= maxBagSize, "CommunityLaunch: Bag size limit exceeded");

        uint256 eventPrice = (usdAmount * 1e18) / _tokensAmount;

        uint256 referralBonus = _calculateReferralBonus(_tokensAmount, _referrer, msg.sender);

        if (bonus) {
            uint256 bonusAmount = _calculateBonus(_tokensAmount);
            _tokensAmount += bonusAmount;
        }

        _tokensAmount += referralBonus;

        require(
            token.balanceOf(address(this)) >= _tokensAmount,
            "CommunityLaunch: Invalid amount for purchase"
        );

        if (_amountIn != 0 && _token == dusdAddress) {
            require(
                tokensAmountByType[0] >= _tokensAmount,
                "CommunityLaunch: Invalid amount to purchase for the selected token"
            );
            tokensAmountByType[0] -= _tokensAmount;
        }

        _createVesting(
            msg.sender,
            uint128(_tokensAmount),
            uint128(block.timestamp),
            vestingParams.cliff,
            duration,
            vestingParams.slicePeriodSeconds,
            lockId
        );

        emit TokensPurchased(
            msg.sender,
            _referrer,
            _tokensAmount,
            saleTokenType,
            inputAmount,
            eventPrice
        );
    }

    function simulateBuy(
        address _beneficiary,
        address _referrer,
        uint256 _usdAmount,
        bool _isBonus
    ) external onlyBot {
        uint256 _tokensAmount = _calculateTokensAmount(_usdAmount, true);
        uint128 duration = vestingParams.duration;
        uint256 lockId = vestingParams.lockId;
        if (_isBonus) {
            _tokensAmount = (_tokensAmount * _calculateFactorBonus(1, true)) / 100;
            duration = duration * 2;
            lockId += 1;
        }
        uint256 eventPrice = (_usdAmount * 1e18) / _tokensAmount;
        _tokensAmount += (_calculateBonus(_tokensAmount) +
            _calculateReferralBonus(_tokensAmount, _referrer, _beneficiary));

        require(
            token.balanceOf(address(this)) >= _tokensAmount,
            "CommunityLaunch: Invalid amount for purchase"
        );

        _createVesting(
            _beneficiary,
            uint128(_tokensAmount),
            uint128(block.timestamp),
            vestingParams.cliff,
            duration,
            vestingParams.slicePeriodSeconds,
            lockId
        );

        emit TokensPurchased(_beneficiary, _referrer, _tokensAmount, 1, _usdAmount, eventPrice);
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

    function _calculateTokensAmount(
        uint256 _usdAmount,
        bool _simulateBuy
    ) private view returns (uint256) {
        if (_simulateBuy && !isSaleActive) {
            return (_usdAmount * 1e18) / endTokenPrice;
        }
        (
            uint256 currentSection,
            uint256 _soldTokens,
            uint256 _tokenPerSection
        ) = _calculateCurrentSection();

        uint256 amount = (_usdAmount * 1e18) / _getTokenPrice(currentSection - 1);
        if (_soldTokens + amount > _tokenPerSection * currentSection) {
            amount = _tokenPerSection * currentSection - _soldTokens;
            uint256 _remainingUsd = _usdAmount -
                ((amount * _getTokenPrice(currentSection - 1)) / 1e18);
            amount += (_remainingUsd * 1e18) / _getTokenPrice(currentSection);
        }

        return amount;
    }

    function _createVesting(
        address _beneficiary,
        uint128 _amount,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        uint256 _lockId
    ) private {
        token.safeTransfer(freezerAddress, _amount);
        ITokenVesting(vestingAddress).createVestingSchedule(
            _beneficiary,
            1718755200, // 19.06.2024
            _cliff,
            _duration,
            _slicePeriodSeconds,
            true,
            _amount,
            vestingParams.vestingType,
            _lockId
        );
    }

    function _getTokenPrice(uint256 section) private view returns (uint256) {
        uint256 _incPricePerSection = (endTokenPrice - startTokenPrice) / (sectionsNumber - 1);

        return startTokenPrice + (_incPricePerSection * section);
    }

    function _calculateCurrentSection() private view returns (uint256, uint256, uint256) {
        uint256 currentSection = 0;
        uint256 _soldTokens = tokensToSale - token.balanceOf(address(this));
        uint256 _tokenPerSection = tokensToSale / sectionsNumber;

        for (uint256 i = 1; i <= sectionsNumber; ++i) {
            if (_tokenPerSection * (i - 1) <= _soldTokens && _soldTokens <= _tokenPerSection * i) {
                currentSection = i;
                break;
            }
        }
        return (currentSection, _soldTokens, _tokenPerSection);
    }

    function _getDUSDToDFIPrice() private view returns (uint256) {
        (uint reserve0, uint reserve1, ) = IVanillaPair(pairAddress).getReserves();
        if (IVanillaPair(pairAddress).token0() != dusdAddress) {
            return (1e18 * reserve0) / reserve1;
        } else {
            return (1e18 * reserve1) / reserve0;
        }
    }

    function _dusdToDFI(uint256 _amount) private view returns (uint256) {
        return (_amount * avgDUSDPrice) / 1e18;
    }

    function _getTokenToUSDPrice(string memory _pair) private view returns (uint256) {
        (, IStateRelayer.DEXInfo memory dex) = IStateRelayer(stateRelayer).getDexPairInfo(_pair);
        uint256 price = (dex.primaryTokenPrice * dex.secondTokenBalance) / dex.firstTokenBalance;
        return 1e36 / price;
    }

    function _dfiToUSD(uint256 _amount) private view returns (uint256) {
        uint256 dfiPrice = _getTokenToUSDPrice("dUSDT-DFI");
        if (dfiPrice > 1e18) {
            return (_amount * 1e18) / dfiPrice;
        } else {
            return (_amount * dfiPrice) / 1e18;
        }
    }

    function _calculateBonus(uint256 _amount) private pure returns (uint256) {
        uint256 bonus = 0;

        if (_amount >= 25000 ether) {
            bonus = (_amount * 1) / 100;
        }
        if (_amount >= 50000 ether) {
            bonus = (_amount * 2) / 100;
        }
        if (_amount >= 100000 ether) {
            bonus = (_amount * 3) / 100;
        }

        return bonus;
    }

    function _calculateReferralBonus(
        uint256 _amount,
        address _referral,
        address _sender
    ) private pure returns (uint256) {
        if (_referral != _sender && _referral != address(0)) {
            return (_amount * 1) / 100;
        } else {
            return 0;
        }
    }

    function _calculateFactorBonus(
        uint256 _tokenId,
        bool _simulateBuy
    ) private view returns (uint256) {
        uint256[] memory factor = tokenFactor[_tokenId];

        if (_simulateBuy && !isSaleActive) {
            return factor[1];
        }

        (uint256 section, , ) = _calculateCurrentSection();
        uint256 _decFactorPerSection = (factor[0] - factor[1]) / (sectionsNumber - 1);

        return factor[0] - (_decFactorPerSection * (section - 1));
    }
}
