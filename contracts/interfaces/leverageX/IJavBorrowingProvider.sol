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

    error OnlyTradingPnlHandler();
    error NotEnoughAssets();
    error OnlyWhiteList();
    error InactiveBuy();
    error InactiveSell();
}
