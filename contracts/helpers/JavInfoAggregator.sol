// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../base/BaseUpgradable.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IJavStakeX.sol";
import "../interfaces/IJavFreezer.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IJavPriceAggregator.sol";
import "../libraries/PriceUtils.sol";
import "../interfaces/helpers/IJavInfoAggregator.sol";

contract JavInfoAggregator is IJavInfoAggregator, BaseUpgradable {
    address public javAddress;
    address public javPool;
    address public vestingAddress;
    address public stakingAddress;
    address public freezerAddress;
    IJavPriceAggregator public priceAggregator;

    mapping(address => bytes32) public priceFeeds;

    address public javlisAddress;
    address public javlisVirtualPool;
    address public ethAddress;
    address public virtualEthPool;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _javAddress,
        address _javPool,
        address _vestingAddress,
        address _stakingAddress,
        address _freezerAddress,
        address _priceAggregator
    ) external initializer {
        javAddress = _javAddress;
        javPool = _javPool;
        vestingAddress = _vestingAddress;
        stakingAddress = _stakingAddress;
        freezerAddress = _freezerAddress;

        priceAggregator = IJavPriceAggregator(_priceAggregator);

        __Base_init();
    }

    function getTotalJavAmount(address _holder) external view returns (uint256) {
        return _getTotalJavAmount(_holder);
    }

    function getJavFreezerAmount(address _holder) external view returns (uint256) {
        return _getJavFreezerAmount(_holder);
    }

    function getJavPrice(uint8 _targetDecimals) external view returns (uint256) {
        return _getJavPrice(_targetDecimals);
    }

    function getJavlisPrice(uint8 _targetDecimals) external view returns (uint256) {
        return _getJavlisPrice(_targetDecimals);
    }

    function setPriceFeed(address _token, bytes32 _feedId) external onlyAdmin {
        priceFeeds[_token] = _feedId;

        emit SetPriceFeed(_token, _feedId);
    }

    function setJavlisAddress(address _javlisAddress) external onlyAdmin {
        javlisAddress = _javlisAddress;

        emit SetJavlisAddress(_javlisAddress);
    }

    function setJavlisVirtualPool(address _javlisVirtualPool) external onlyAdmin {
        javlisVirtualPool = _javlisVirtualPool;

        emit SetJavlisVirtualPool(_javlisVirtualPool);
    }

    function setEthAddress(address _ethAddress) external onlyAdmin {
        ethAddress = _ethAddress;

        emit SetEthAddress(_ethAddress);
    }

    function setVirtualEthPool(address _virtualEthPool) external onlyAdmin {
        virtualEthPool = _virtualEthPool;

        emit SetVirtualEthPool(_virtualEthPool);
    }

    function _getJavPrice(uint8 _targetDecimals) private view returns (uint256) {
        uint256 javEthPrice;
        uint256 precision = 10 ** _targetDecimals;
        IPool pool = IPool(javPool);
        address ethToken = pool.token0() == javAddress ? pool.token1() : pool.token0();
        if (pool.token0() == javAddress) {
            javEthPrice = (pool.reserve1() * precision) / pool.reserve0();
        } else {
            javEthPrice = (pool.reserve0() * precision) / pool.reserve1();
        }
        uint256 ethPrice = _getUsdPrice(priceFeeds[ethToken], _targetDecimals);

        return (javEthPrice * ethPrice) / precision;
    }

    function _getJavlisPrice(uint8 _targetDecimals) private view returns (uint256) {
        uint256 precision = 10 ** _targetDecimals;
        uint256 javlisVirtualPrice;
        uint256 virtualEthPrice;

        IUniswapV2Pair _javlisVirtualPool = IUniswapV2Pair(javlisVirtualPool);

        (uint112 javlisVirtualRes0, uint112 javlisVirtualRes1, ) = _javlisVirtualPool.getReserves();

        if (_javlisVirtualPool.token0() == javlisAddress) {
            javlisVirtualPrice = (javlisVirtualRes1 * precision) / javlisVirtualRes0;
        } else {
            javlisVirtualPrice = (javlisVirtualRes0 * precision) / javlisVirtualRes1;
        }

        IUniswapV2Pair _virtualEthPool = IUniswapV2Pair(virtualEthPool);

        (uint112 virtualEthRes0, uint112 virtualEthRes1, ) = _virtualEthPool.getReserves();

        if (_virtualEthPool.token0() == ethAddress) {
            virtualEthPrice = (virtualEthRes0 * precision) / virtualEthRes1;
        } else {
            virtualEthPrice = (virtualEthRes1 * precision) / virtualEthRes0;
        }

        uint256 javlisEthPrice = (javlisVirtualPrice * virtualEthPrice) / precision;

        uint256 ethPrice = _getUsdPrice(priceFeeds[ethAddress], _targetDecimals);

        return (javlisEthPrice * ethPrice) / precision;
    }

    function _getTotalJavAmount(address _user) private view returns (uint256 _totalAmount) {
        uint256 stakingAmount = IJavStakeX(stakingAddress).userShares(0, _user);
        if (stakingAmount > 0) {
            _totalAmount += stakingAmount;
        }

        _totalAmount += _getJavFreezerAmount(_user);

        uint256 vestingCount = ITokenVesting(vestingAddress).holdersVestingCount(_user);
        if (vestingCount > 0) {
            for (uint256 i = 0; i < vestingCount; ++i) {
                ITokenVesting.VestingSchedule memory schedule = ITokenVesting(vestingAddress)
                    .getVestingScheduleByAddressAndIndex(_user, i);
                if (schedule.released != schedule.amountTotal && !schedule.revoked) {
                    _totalAmount += (schedule.amountTotal - schedule.released);
                }
            }
        }
    }

    function _getJavFreezerAmount(address _user) private view returns (uint256 _freezerAmount) {
        if (IJavFreezer(freezerAddress).userDepositTokens(0, _user) > 0) {
            uint256 lastId = IJavFreezer(freezerAddress).getUserLastDepositId(0, _user);
            for (uint256 i = 0; i <= lastId; ++i) {
                IJavFreezer.UserDeposit memory depositDetails = IJavFreezer(freezerAddress)
                    .userDeposit(_user, 0, i);
                if (!depositDetails.is_finished) {
                    _freezerAmount += depositDetails.depositTokens;
                }
            }
        }
    }

    function _getUsdPrice(
        bytes32 _priceFeed,
        uint8 _targetDecimals
    ) private view returns (uint256) {
        IJavPriceAggregator.Price memory price = priceAggregator.getPriceUnsafe(_priceFeed);
        return PriceUtils.convertToUint(price.price, price.expo, _targetDecimals);
    }
}
