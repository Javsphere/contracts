// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/leverageX/CollateralUtils.sol";
import "../interfaces/leverageX/IXVault.sol";
import "../base/BaseUpgradable.sol";

import "../abstract/TearmsAndCondUtils.sol";
import "../interfaces/helpers/IJavInfoAggregator.sol";
import "../interfaces/helpers/IGeneralErrors.sol";

contract XVault is ERC4626Upgradeable, BaseUpgradable, IXVault, TermsAndCondUtils, IGeneralErrors {
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

    address public termsAndConditionsAddress;
    address public javInfoAggregator;

    uint32[] public baseFees; //1e4
    uint32[] public usdThresholds; // clear
    uint32[] public javThresholds; // clear
    uint32[] public reductionFactors; //1e4
    uint32[] public sellFees; //1e4

    uint256 public lastUpdateEpoch;

    modifier checks(uint256 assetsOrShares) {
        _checks(assetsOrShares);
        _;
    }

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

    // Manage parameters
    function updatePnlHandler(address newValue) external onlyOwner {
        if (newValue == address(0)) revert AddressZero();
        pnlHandler = newValue;
        emit PnlHandlerUpdated(newValue);
    }

    function updateMaxSupplyIncreaseDailyP(uint256 newValue) external onlyAdmin {
        if (newValue > MAX_SUPPLY_INCREASE_DAILY_P) revert AboveMax();
        maxSupplyIncreaseDailyP = newValue;
        emit MaxSupplyIncreaseDailyPUpdated(newValue);
    }

    function setTermsAndConditionsAddress(
        address _termsAndConditionsAddress
    ) external onlyAdmin nonZeroAddress(_termsAndConditionsAddress) {
        termsAndConditionsAddress = _termsAndConditionsAddress;

        emit SetTermsAndConditionsAddress(_termsAndConditionsAddress);
    }

    function setJavInfoAggregator(
        address _javInfoAggregator
    ) external onlyAdmin nonZeroAddress(_javInfoAggregator) {
        javInfoAggregator = _javInfoAggregator;

        emit SetJavInfoAggregator(_javInfoAggregator);
    }

    function setBuyConfiguration(
        uint32[] memory _baseFees,
        uint32[] memory _usdThresholds
    ) external onlyAdmin {
        require(_baseFees.length == _usdThresholds.length, InvalidInputLength());

        baseFees = _baseFees;
        usdThresholds = _usdThresholds;

        emit SetBuyConfiguration(_baseFees, _usdThresholds);
    }

    function setJavAmountConfiguration(
        uint32[] memory _javThresholds,
        uint32[] memory _reductionFactors
    ) external onlyAdmin {
        require(_javThresholds.length == _reductionFactors.length, InvalidInputLength());

        javThresholds = _javThresholds;
        reductionFactors = _reductionFactors;

        emit SetJavAmountConfiguration(_javThresholds, _reductionFactors);
    }

    function setSellFees(uint32[] memory _sellFees) external onlyAdmin {
        require(javThresholds.length == _sellFees.length, InvalidInputLength());
        sellFees = _sellFees;

        emit SetSellFees(_sellFees);
    }

    function updateWithdrawEpochsLock(uint256 _newValue) external onlyOwner {
        withdrawEpochsLock = _newValue;
        emit UpdateWithdrawEpochsLock(_newValue);
    }

    function updateEpochDuration(uint256 _newValue) external onlyOwner {
        lastUpdateEpoch = getCurrentEpoch();
        epochDuration = _newValue;

        emit UpdateEpochDuration(_newValue);
    }

    function makeWithdrawRequest(uint256 shares, address owner) external {
        if (shares > maxRedeem(owner))
            revert ERC4626ExceededMaxWithdraw(owner, shares, maxRedeem(owner));

        uint256 currentEpoch = getCurrentEpoch();

        address sender = _msgSender();
        uint256 allowance = allowance(owner, sender);

        if (sender != owner && (allowance == 0 || allowance < shares)) revert NotAllowed();

        if (totalSharesBeingWithdrawn(owner) + shares > balanceOf(owner)) revert AboveMax();

        uint256 unlockEpoch = currentEpoch + withdrawEpochsLock;
        withdrawRequests[owner][unlockEpoch] += shares;

        emit WithdrawRequested(sender, owner, shares, currentEpoch, unlockEpoch);
    }

    function cancelWithdrawRequest(address owner, uint256 unlockEpoch) external {
        uint256 currentEpoch = getCurrentEpoch();
        require(withdrawRequests[owner][unlockEpoch] > 0, ZeroValue());

        uint256 shares = withdrawRequests[owner][unlockEpoch];

        address sender = _msgSender();
        uint256 allowance = allowance(owner, sender);

        if (sender != owner && (allowance == 0 || allowance < shares)) revert NotAllowed();

        withdrawRequests[owner][unlockEpoch] = 0;

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

        updateShareToAssetsPrice();
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

        updateShareToAssetsPrice();
        tryUpdateCurrentMaxSupply();

        emit AssetsReceived(sender, user, assets, assets);
    }

    function tvl() external view returns (uint256) {
        return (maxAccPnlPerToken() * totalSupply()) / PRECISION_18;
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

    // Override ERC-4626 interactions (call scaleVariables on every deposit / withdrawal)
    function deposit(
        uint256 assets,
        address receiver
    ) public override checks(assets) onlyAgreeToTerms(termsAndConditionsAddress) returns (uint256) {
        uint256 javPriceUsd = IJavInfoAggregator(javInfoAggregator).getJavPrice(18);
        uint256 inputAmountUsd = (assets * javPriceUsd) / PRECISION_18;
        uint256 feeP = _calculateFeeP(inputAmountUsd, _msgSender(), true);
        uint256 fee = (assets * feeP) / 1e4;
        uint256 clearAssets = assets - fee;
        if (clearAssets > maxDeposit(receiver)) {
            revert ERC4626ExceededMaxDeposit(receiver, maxDeposit(receiver), clearAssets);
        }

        uint256 shares = previewDeposit(clearAssets);
        scaleVariables(shares, clearAssets, true);

        _deposit(_msgSender(), receiver, clearAssets, shares);

        IERC20Extended(asset()).burnFrom(_msgSender(), fee);

        return shares;
    }

    function withdraw(
        uint256 epoch,
        address receiver,
        address owner
    ) public override onlyAgreeToTerms(termsAndConditionsAddress) returns (uint256) {
        require(epoch <= getCurrentEpoch(), WrongIndex());
        require(withdrawRequests[owner][epoch] > 0, ZeroValue());

        uint256 shares = withdrawRequests[owner][epoch];
        uint256 assets = previewRedeem(shares);

        uint256 javPriceUsd = IJavInfoAggregator(javInfoAggregator).getJavPrice(18);
        uint256 inputAmountUsd = (assets * javPriceUsd) / PRECISION_18;

        uint256 feeP = _calculateFeeP(inputAmountUsd, _msgSender(), false);
        uint256 fee = (assets * feeP) / 1e4;
        uint256 clearAssets = assets - fee;

        withdrawRequests[owner][epoch] = 0;

        scaleVariables(shares, assets, false);
        _withdraw(_msgSender(), receiver, owner, clearAssets, shares);

        IERC20Extended(asset()).burn(fee);
        return shares;
    }

    // View helper functions
    function getCurrentEpoch() public view returns (uint256) {
        return lastUpdateEpoch + (block.timestamp - commencementTimestamp) / epochDuration;
    }

    function clearEpochNumber() external view returns (uint256) {
        return (block.timestamp - commencementTimestamp) / epochDuration;
    }

    function maxAccPnlPerToken() public view returns (uint256) {
        // PRECISION_18
        return PRECISION_18 + accRewardsPerToken;
    }

    function totalSharesBeingWithdrawn(address owner) public view returns (uint256 shares) {
        uint256 currentEpoch = getCurrentEpoch();
        for (uint256 i = currentEpoch; i <= currentEpoch + withdrawEpochsLock; ++i) {
            shares += withdrawRequests[owner][i];
        }
    }

    // Override ERC-4626 view functions
    function decimals() public view override(ERC4626Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    function maxMint(address) public view override returns (uint256) {
        return
            accPnlPerToken > 0
                ? currentMaxSupply - Math.min(currentMaxSupply, totalSupply())
                : type(uint256).max;
    }

    function maxDeposit(address owner) public view override returns (uint256) {
        return _convertToAssets(maxMint(owner), Math.Rounding.Floor);
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
        if (shares == type(uint256).max && shareToAssetsPrice >= PRECISION_18) {
            return shares;
        }
        return shares.mulDiv(shareToAssetsPrice, PRECISION_18, rounding);
    }

    // Private helper functions
    function updateShareToAssetsPrice() private {
        shareToAssetsPrice =
            maxAccPnlPerToken() -
            (accPnlPerToken > 0 ? uint256(accPnlPerToken) : uint256(0)); // PRECISION_18
        emit ShareToAssetsPriceUpdated(shareToAssetsPrice);
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

    function _calculateFeeP(
        uint256 _usdAmount,
        address _user,
        bool _isDeposit
    ) private view returns (uint256) {
        uint256 _javFreezerAmount = IJavInfoAggregator(javInfoAggregator).getJavFreezerAmount(
            _user
        );
        uint32 baseFee;
        uint32 reductionFactor;

        if (!_isDeposit) {
            for (uint8 i = uint8(javThresholds.length); i > 0; --i) {
                if (_javFreezerAmount >= javThresholds[i - 1] * PRECISION_18) {
                    return sellFees[i - 1];
                }
            }
        }

        for (uint8 i = uint8(usdThresholds.length); i > 0; --i) {
            if (_usdAmount >= usdThresholds[i - 1] * PRECISION_18) {
                baseFee = baseFees[i - 1];
                break;
            }
        }

        for (uint8 i = uint8(javThresholds.length); i > 0; --i) {
            if (_javFreezerAmount >= javThresholds[i - 1] * PRECISION_18) {
                reductionFactor = reductionFactors[i - 1];
                break;
            }
        }

        return (baseFee * reductionFactor) / 1e4;
    }

    function _checks(uint256 assetsOrShares) private view {
        if (shareToAssetsPrice == 0) revert PriceZero();
        if (assetsOrShares == 0) revert ValueZero();
    }

    function _assetIERC20() private view returns (IERC20) {
        return IERC20(asset());
    }
}
