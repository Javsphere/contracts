// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

interface IJavBorrowingProvider {
    function distributeReward(uint8 _collateralIndex, uint256 assets) external;

    function sendAssets(uint8 _collateralIndex, uint256 assets, address receiver) external;

    function receiveAssets(uint8 _collateralIndex, uint256 assets, address user) external;

    function tvl() external view returns (uint256);

    event ShareToAssetsPriceUpdated(uint256 newValue);
    event PnlHandlerUpdated(address newValue);
    event RewardDistributed(
        address indexed sender,
        uint256 indexed collateralIndex,
        uint256 assets,
        uint256 usdAmount
    );
    event AssetsSent(address indexed sender, address indexed receiver, uint256 assets);
    event AssetsReceived(
        address indexed sender,
        address indexed user,
        uint256 assets,
        uint256 assetsLessDeplete
    );

    event BuyActiveStateUpdated(bool isActive);
    event SellActiveStateUpdated(bool isActive);
    event WhiteListAdded(address indexed _address);
    event WhiteListRemoved(address indexed _address);
    event SetJavBurner(address indexed _address);
    event SetJavInfoAggregator(address indexed _address);
    event SetSellFees(uint32[] sellFees);
    event SetMinBuyAmountUsd(uint256 minBuyAmountUsd);
    event SetBuyConfiguration(uint32[] baseFees, uint32[] usdThresholds);
    event SetJavAmountConfiguration(uint32[] javThresholds, uint32[] reductionFactors);

    error OnlyTradingPnlHandler();
    error NotEnoughAssets();
    error OnlyWhiteList();
    error InactiveBuy();
    error InactiveSell();
    error BelowMinBuyAmount();
}
