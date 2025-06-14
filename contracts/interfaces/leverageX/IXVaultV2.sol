// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

interface IXVaultV2 {
    struct ContractAddresses {
        address asset;
        address pnlHandler;
    }

    struct Meta {
        string name;
        string symbol;
    }

    function sendAssets(uint8 __, uint256 assets, address receiver) external;

    function receiveAssets(uint8 __, uint256 assets, address user) external;

    function distributeReward(uint8 __, uint256 assets) external;

    function tvl() external view returns (uint256);

    event PnlHandlerUpdated(address newValue);
    event MaxDailyAccPnlDeltaUpdated(uint256 newValue);
    event MaxSupplyIncreaseDailyPUpdated(uint256 newValue);
    event MaxDiscountThresholdPUpdated(uint256 newValue);

    event CurrentMaxSupplyUpdated(uint256 newValue);
    event DailyAccPnlDeltaReset();
    event ShareToAssetsPriceUpdated(uint256 newValue);
    event UpdateWithdrawEpochsLock(uint256 newValue);
    event UpdateEpochDuration(uint256 newValue);
    event WithdrawRequested(
        address indexed sender,
        address indexed owner,
        uint256 shares,
        uint256 currEpoch,
        uint256 indexed unlockEpoch
    );
    event WithdrawCanceled(
        address indexed sender,
        address indexed owner,
        uint256 shares,
        uint256 currEpoch,
        uint256 indexed unlockEpoch
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 unlockEpoch
    );

    event RewardDistributed(address indexed sender, uint256 assets);

    event AssetsSent(address indexed sender, address indexed receiver, uint256 assets);
    event AssetsReceived(
        address indexed sender,
        address indexed user,
        uint256 assets,
        uint256 assetsLessDeplete
    );

    event SetSellFeeP(uint32 sellFeeP);
    event SetBuyConfiguration(uint32[] baseFees, uint32[] usdThresholds);

    error OnlyTradingPnlHandler();
    error PriceZero();
    error ValueZero();
    error AboveMax();
    error WrongValue();
    error WrongValues();
    error PendingWithdrawal();
    error EndOfEpoch();
    error NotEnoughAssets();
    error MaxDailyPnl();
}
