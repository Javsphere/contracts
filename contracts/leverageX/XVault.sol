// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/leverageX/CollateralUtils.sol";
import "../interfaces/leverageX/IXVault.sol";
import "../base/BaseUpgradable.sol";

contract XVault is ERC4626Upgradeable, BaseUpgradable, IXVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    CollateralUtils.CollateralConfig public collateralConfig;

    address public pnlHandler;

    // Parameters (constant)
    uint256 constant PRECISION_18 = 1e18;
    uint256 constant MIN_DAILY_ACC_PNL_DELTA = PRECISION_18 / 10; // 0.1, price delta (1e18)
    uint256 constant MAX_SUPPLY_INCREASE_DAILY_P = 50 * PRECISION_18; // 50% / day, when under collat (1e18)
    uint256 public withdrawEpochsLock; // epochs withdraw locks at over collat thresholds

    // Parameters (adjustable)
    uint256 public maxDailyAccPnlDelta; // PRECISION_18 (max daily price delta from closed pnl)
    uint256 public maxSupplyIncreaseDailyP; // PRECISION_18 (% per day, when under collat)

    // Price state
    uint256 public shareToAssetsPrice; // PRECISION_18
    int256 public accPnlPerToken; // PRECISION_18 (updated in real-time)
    uint256 public accRewardsPerToken; // PRECISION_18

    // Closed Pnl state
    int256 public dailyAccPnlDelta; // PRECISION_18
    uint256 public lastDailyAccPnlDeltaReset; // timestamp

    // Epochs state (withdrawals)
    uint256 public commencementTimestamp; // global id
    uint256 public epochDuration; // timestamp

    // Deposit / Withdraw state
    uint256 public currentMaxSupply; // collateralConfig.precision
    uint256 public lastMaxSupplyUpdate; // timestamp
    mapping(address => mapping(uint256 => uint256)) public withdrawRequests; // owner => unlock epoch => shares

    // Statistics (not used for contract logic)
    uint256 public totalDeposited; // collateralConfig.precision (assets)
    int256 public totalClosedPnl; // collateralConfig.precision (assets)
    uint256 public totalRewards; // collateralConfig.precision (assets)
    int256 public totalLiability; // collateralConfig.precision (assets)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initializer function called when this contract is deployed
    function initialize(
        Meta memory _meta,
        ContractAddresses memory _contractAddresses,
        uint256 _maxDailyAccPnlDelta,
        uint256 _maxSupplyIncreaseDailyP,
        uint256 _commencementTimestamp,
        uint256 _epochDuration,
        uint256 _withdrawEpochsLock
    ) external initializer {
        if (
            !(_contractAddresses.asset != address(0) &&
                _contractAddresses.pnlHandler != address(0) &&
                _maxDailyAccPnlDelta >= MIN_DAILY_ACC_PNL_DELTA &&
                _maxSupplyIncreaseDailyP <= MAX_SUPPLY_INCREASE_DAILY_P)
        ) {
            revert WrongValues();
        }

        pnlHandler = _contractAddresses.pnlHandler;

        maxDailyAccPnlDelta = _maxDailyAccPnlDelta;
        maxSupplyIncreaseDailyP = _maxSupplyIncreaseDailyP;

        commencementTimestamp = _commencementTimestamp;
        epochDuration = _epochDuration;

        shareToAssetsPrice = PRECISION_18;
        withdrawEpochsLock = _withdrawEpochsLock;
        collateralConfig = CollateralUtils.getCollateralConfig(_contractAddresses.asset);

        __ERC20_init(_meta.name, _meta.symbol); // xToken
        __ERC4626_init(IERC20Metadata(_contractAddresses.asset)); // Token
        __Base_init();
    }

    modifier checks(uint256 assetsOrShares) {
        _checks(assetsOrShares);
        _;
    }

    function _checks(uint256 assetsOrShares) private view {
        if (shareToAssetsPrice == 0) revert PriceZero();
        if (assetsOrShares == 0) revert ValueZero();
    }

    function updatePnlHandler(address newValue) external onlyOwner {
        if (newValue == address(0)) revert AddressZero();
        pnlHandler = newValue;
        emit PnlHandlerUpdated(newValue);
    }

    // Manage parameters

    function updateMaxSupplyIncreaseDailyP(uint256 newValue) external onlyAdmin {
        if (newValue > MAX_SUPPLY_INCREASE_DAILY_P) revert AboveMax();
        maxSupplyIncreaseDailyP = newValue;
        emit MaxSupplyIncreaseDailyPUpdated(newValue);
    }

    function updateWithdrawEpochsLock(uint256 _newValue) external onlyOwner {
        withdrawEpochsLock = _newValue;
        emit UpdateWithdrawEpochsLock(_newValue);
    }

    // View helper functions
    function maxAccPnlPerToken() public view returns (uint256) {
        // PRECISION_18
        return PRECISION_18 + accRewardsPerToken;
    }

    function collateralizationP() external view returns (uint256) {
        // PRECISION_18 (%)
        uint256 _maxAccPnlPerToken = maxAccPnlPerToken();
        return (_maxAccPnlPerToken * 100 * PRECISION_18) / _maxAccPnlPerToken;
    }

    function totalSharesBeingWithdrawn(address owner) public view returns (uint256 shares) {
        uint256 currentEpoch = getCurrentEpoch();
        for (uint256 i = currentEpoch; i <= currentEpoch + withdrawEpochsLock; ++i) {
            shares += withdrawRequests[owner][i];
        }
    }

    // external helper functions
    function tryUpdateCurrentMaxSupply() public {
        if (block.timestamp - lastMaxSupplyUpdate >= 24 hours) {
            currentMaxSupply =
                (totalSupply() * (PRECISION_18 * 100 + maxSupplyIncreaseDailyP)) /
                (PRECISION_18 * 100);
            lastMaxSupplyUpdate = block.timestamp;

            emit CurrentMaxSupplyUpdated(currentMaxSupply);
        }
    }

    function tryResetDailyAccPnlDelta() public {
        if (block.timestamp - lastDailyAccPnlDeltaReset >= 24 hours) {
            dailyAccPnlDelta = 0;
            lastDailyAccPnlDeltaReset = block.timestamp;

            emit DailyAccPnlDeltaReset();
        }
    }

    // Private helper functions
    function updateShareToAssetsPrice() private {
        shareToAssetsPrice = maxAccPnlPerToken(); // PRECISION_18
        emit ShareToAssetsPriceUpdated(shareToAssetsPrice);
    }

    function _assetIERC20() private view returns (IERC20) {
        return IERC20(asset());
    }

    // Override ERC-20 functions (prevent sending to address that is withdrawing)
    function transfer(
        address to,
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20) returns (bool) {
        address sender = _msgSender();
        if (totalSharesBeingWithdrawn(sender) > balanceOf(sender) - amount)
            revert PendingWithdrawal();

        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20) returns (bool) {
        if (totalSharesBeingWithdrawn(from) > balanceOf(from) - amount) revert PendingWithdrawal();

        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }

    // Override ERC-4626 view functions
    function decimals() public view override(ERC4626Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override returns (uint256 shares) {
        return assets.mulDiv(PRECISION_18, shareToAssetsPrice, rounding);
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override returns (uint256 assets) {
        // Prevent overflow when called from maxDeposit with maxMint = uint256.max
        if (shares == type(uint256).max && shareToAssetsPrice >= PRECISION_18) {
            return shares;
        }
        return shares.mulDiv(shareToAssetsPrice, PRECISION_18, rounding);
    }

    function maxMint(address) public view override returns (uint256) {
        return
            currentMaxSupply > 0
                ? currentMaxSupply - Math.min(currentMaxSupply, totalSupply())
                : type(uint256).max;
    }

    function maxDeposit(address owner) public view override returns (uint256) {
        return _convertToAssets(maxMint(owner), Math.Rounding.Floor);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(maxRedeem(owner), Math.Rounding.Floor);
    }

    // Override ERC-4626 interactions (call scaleVariables on every deposit / withdrawal)
    function deposit(
        uint256 assets,
        address receiver
    ) public override checks(assets) returns (uint256) {
        if (assets > maxDeposit(receiver))
            revert ERC4626ExceededMaxDeposit(receiver, maxDeposit(receiver), assets);

        uint256 shares = previewDeposit(assets);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override checks(assets) returns (uint256) {
        if (assets > maxWithdraw(owner))
            revert ERC4626ExceededMaxWithdraw(receiver, maxWithdraw(owner), assets);

        uint256 shares = previewWithdraw(assets);
        withdrawRequests[owner][getCurrentEpoch()] -= shares;

        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override checks(shares) returns (uint256) {
        if (shares > maxRedeem(owner))
            revert ERC4626ExceededMaxRedeem(owner, shares, maxRedeem(owner));

        withdrawRequests[owner][getCurrentEpoch()] -= shares;

        uint256 assets = previewRedeem(shares);
        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    function scaleVariables(uint256 shares, uint256 assets, bool isDeposit) private {
        uint256 supply = totalSupply();

        if (accPnlPerToken < 0) {
            accPnlPerToken =
                (accPnlPerToken * int256(supply)) /
                (isDeposit ? int256(supply + shares) : int256(supply - shares));
        } else if (accPnlPerToken > 0) {
            totalLiability +=
                ((int256(shares) * totalLiability) / int256(supply)) *
                (isDeposit ? int256(1) : int256(-1));
        }

        totalDeposited = isDeposit ? totalDeposited + assets : totalDeposited - assets;
    }

    function makeWithdrawRequest(uint256 shares, address owner) external {
        uint256 currentEpoch = getCurrentEpoch();

        address sender = _msgSender();
        uint256 allowance = allowance(owner, sender);

        if (sender != owner && (allowance == 0 || allowance < shares)) revert NotAllowed();

        if (totalSharesBeingWithdrawn(owner) + shares > balanceOf(owner)) revert AboveMax();

        uint256 unlockEpoch = currentEpoch + withdrawEpochsLock;
        withdrawRequests[owner][unlockEpoch] += shares;

        emit WithdrawRequested(sender, owner, shares, currentEpoch, unlockEpoch);
    }

    function cancelWithdrawRequest(uint256 shares, address owner, uint256 unlockEpoch) external {
        uint256 currentEpoch = getCurrentEpoch();
        if (shares > withdrawRequests[owner][unlockEpoch]) revert AboveMax();

        address sender = _msgSender();
        uint256 allowance = allowance(owner, sender);

        if (sender != owner && (allowance == 0 || allowance < shares)) revert NotAllowed();

        withdrawRequests[owner][unlockEpoch] -= shares;

        emit WithdrawCanceled(sender, owner, shares, currentEpoch, unlockEpoch);
    }

    // @param __: a placeholder to match the function selector
    function distributeReward(uint8 __, uint256 assets) external {
        address sender = _msgSender();
        _assetIERC20().safeTransferFrom(sender, address(this), assets);

        accRewardsPerToken +=
            (assets * collateralConfig.precisionDelta * collateralConfig.precision) /
            totalSupply();
        updateShareToAssetsPrice();

        totalRewards += assets;
        totalDeposited += assets;

        emit RewardDistributed(sender, assets);
    }

    // @param __: a placeholder to match the function selector
    function sendAssets(uint8 __, uint256 assets, address receiver) external {
        address sender = _msgSender();
        if (sender != pnlHandler) revert OnlyTradingPnlHandler();

        int256 accPnlDelta = int256(
            assets.mulDiv(
                collateralConfig.precisionDelta * collateralConfig.precision,
                totalSupply(),
                Math.Rounding.Ceil
            )
        );

        accPnlPerToken += accPnlDelta;
        if (accPnlPerToken > int256(maxAccPnlPerToken())) revert NotEnoughAssets();

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta += accPnlDelta;
        if (dailyAccPnlDelta > int256(maxDailyAccPnlDelta)) revert MaxDailyPnl();

        totalLiability += int256(assets);
        totalClosedPnl += int256(assets);

        tryUpdateCurrentMaxSupply();

        SafeERC20.safeTransfer(_assetIERC20(), receiver, assets);

        emit AssetsSent(sender, receiver, assets);
    }

    // @param __: a placeholder to match the function selector
    function receiveAssets(uint8 __, uint256 assets, address user) external {
        address sender = _msgSender();
        _assetIERC20().safeTransferFrom(sender, address(this), assets);

        int256 accPnlDelta = int256(
            (assets * collateralConfig.precisionDelta * collateralConfig.precision) / totalSupply()
        );
        accPnlPerToken -= accPnlDelta;

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta -= accPnlDelta;

        totalLiability -= int256(assets);
        totalClosedPnl -= int256(assets);

        tryUpdateCurrentMaxSupply();

        emit AssetsReceived(sender, user, assets, assets);
    }

    function tvl() external view returns (uint256) {
        return (maxAccPnlPerToken() * totalSupply()) / PRECISION_18;
    }

    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - commencementTimestamp) / epochDuration;
    }
}
