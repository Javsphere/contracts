// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/trade/libraries/IReferralsUtils.sol";
import "../../interfaces/trade/IGeneralErrors.sol";
import "../../interfaces/IERC20Extended.sol";

import "./AddressStoreUtils.sol";
import "./StorageUtils.sol";

/**
 * @custom:version 8
 * @dev JavReferrals facet internal library
 */
library ReferralsUtils {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e10;
    uint256 private constant MAX_ALLY_FEE_P = 50;
    uint256 private constant MAX_START_REFERRER_FEE_P = 100;
    uint256 private constant MAX_OPEN_FEE_P = 50;

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function initializeReferrals(
        uint256 _allyFeeP,
        uint256 _startReferrerFeeP,
        uint256 _openFeeP,
        uint256 _targetVolumeUsd
    ) internal {
        if (
            _allyFeeP > MAX_ALLY_FEE_P ||
            _startReferrerFeeP > MAX_START_REFERRER_FEE_P ||
            _openFeeP > MAX_OPEN_FEE_P ||
            _targetVolumeUsd == 0
        ) revert IGeneralErrors.WrongParams();

        IReferralsUtils.ReferralsStorage storage s = _getStorage();

        s.allyFeeP = _allyFeeP;
        s.startReferrerFeeP = _startReferrerFeeP;
        s.openFeeP = _openFeeP;
        s.targetVolumeUsd = _targetVolumeUsd;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function updateAllyFeeP(uint256 _value) internal {
        if (_value > MAX_ALLY_FEE_P) revert IGeneralErrors.AboveMax();

        _getStorage().allyFeeP = _value;

        emit IReferralsUtils.UpdatedAllyFeeP(_value);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function updateStartReferrerFeeP(uint256 _value) internal {
        if (_value > MAX_START_REFERRER_FEE_P) revert IGeneralErrors.AboveMax();

        _getStorage().startReferrerFeeP = _value;

        emit IReferralsUtils.UpdatedStartReferrerFeeP(_value);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function updateReferralsOpenFeeP(uint256 _value) internal {
        if (_value > MAX_OPEN_FEE_P) revert IGeneralErrors.AboveMax();

        _getStorage().openFeeP = _value;

        emit IReferralsUtils.UpdatedOpenFeeP(_value);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function updateReferralsTargetVolumeUsd(uint256 _value) internal {
        if (_value == 0) revert IGeneralErrors.ZeroValue();

        _getStorage().targetVolumeUsd = _value;

        emit IReferralsUtils.UpdatedTargetVolumeUsd(_value);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function whitelistAllies(address[] calldata _allies) internal {
        for (uint256 i = 0; i < _allies.length; ++i) {
            _whitelistAlly(_allies[i]);
        }
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function unwhitelistAllies(address[] calldata _allies) internal {
        for (uint256 i = 0; i < _allies.length; ++i) {
            _unwhitelistAlly(_allies[i]);
        }
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function whitelistReferrers(
        address[] calldata _referrers,
        address[] calldata _allies
    ) internal {
        if (_referrers.length != _allies.length) revert IGeneralErrors.WrongLength();

        for (uint256 i = 0; i < _referrers.length; ++i) {
            _whitelistReferrer(_referrers[i], _allies[i]);
        }
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function unwhitelistReferrers(address[] calldata _referrers) internal {
        for (uint256 i = 0; i < _referrers.length; ++i) {
            _unwhitelistReferrer(_referrers[i]);
        }
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function registerPotentialReferrer(address _trader, address _referrer) internal {
        IReferralsUtils.ReferralsStorage storage s = _getStorage();
        IReferralsUtils.ReferrerDetails storage r = s.referrerDetails[_referrer];

        if (s.referrerByTrader[_trader] != address(0) || _referrer == address(0) || !r.active) {
            return;
        }

        s.referrerByTrader[_trader] = _referrer;
        r.tradersReferred.push(_trader);

        emit IReferralsUtils.ReferrerRegistered(_trader, _referrer);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function distributeReferralReward(
        address _trader,
        uint256 _volumeUsd, // 1e18
        uint256 _pairOpenFeeP,
        uint256 _javPriceUsd // PRECISION (1e10)
    ) internal returns (uint256) {
        IReferralsUtils.ReferralsStorage storage s = _getStorage();

        address referrer = s.referrerByTrader[_trader];
        IReferralsUtils.ReferrerDetails storage r = s.referrerDetails[referrer];

        if (!r.active) {
            return 0;
        }

        uint256 referrerRewardValueUsd = (_volumeUsd *
            getReferrerFeeP(_pairOpenFeeP, r.volumeReferredUsd)) /
            PRECISION /
            100;

        uint256 referrerRewardJav = (referrerRewardValueUsd * PRECISION) / _javPriceUsd;

        IReferralsUtils.AllyDetails storage a = s.allyDetails[r.ally];

        uint256 allyRewardValueUsd;
        uint256 allyRewardJav;

        if (a.active) {
            uint256 allyFeeP = s.allyFeeP;

            allyRewardValueUsd = (referrerRewardValueUsd * allyFeeP) / 100;
            allyRewardJav = (referrerRewardJav * allyFeeP) / 100;

            a.volumeReferredUsd += _volumeUsd;
            a.pendingRewardsJav += allyRewardJav;
            a.totalRewardsJav += allyRewardJav;
            a.totalRewardsValueUsd += allyRewardValueUsd;

            referrerRewardValueUsd -= allyRewardValueUsd;
            referrerRewardJav -= allyRewardJav;

            emit IReferralsUtils.AllyRewardDistributed(
                r.ally,
                _trader,
                _volumeUsd,
                allyRewardJav,
                allyRewardValueUsd
            );
        }

        r.volumeReferredUsd += _volumeUsd;
        r.pendingRewardsJav += referrerRewardJav;
        r.totalRewardsJav += referrerRewardJav;
        r.totalRewardsValueUsd += referrerRewardValueUsd;

        emit IReferralsUtils.ReferrerRewardDistributed(
            referrer,
            _trader,
            _volumeUsd,
            referrerRewardJav,
            referrerRewardValueUsd
        );

        return referrerRewardValueUsd + allyRewardValueUsd;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function claimAllyRewards() internal {
        IReferralsUtils.AllyDetails storage a = _getStorage().allyDetails[msg.sender];
        uint256 rewardsJav = a.pendingRewardsJav;

        if (rewardsJav == 0) revert IReferralsUtils.NoPendingRewards();

        a.pendingRewardsJav = 0;
        IERC20(AddressStoreUtils.getAddresses().rewardsToken).safeTransfer(msg.sender, rewardsJav);

        emit IReferralsUtils.AllyRewardsClaimed(msg.sender, rewardsJav);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function claimReferrerRewards() internal {
        IReferralsUtils.ReferrerDetails storage r = _getStorage().referrerDetails[msg.sender];
        uint256 rewardsJav = r.pendingRewardsJav;

        if (rewardsJav == 0) revert IReferralsUtils.NoPendingRewards();

        r.pendingRewardsJav = 0;
        IERC20(AddressStoreUtils.getAddresses().rewardsToken).safeTransfer(msg.sender, rewardsJav);

        emit IReferralsUtils.ReferrerRewardsClaimed(msg.sender, rewardsJav);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferrerFeeP(
        uint256 _pairOpenFeeP,
        uint256 _volumeReferredUsd
    ) internal view returns (uint256) {
        IReferralsUtils.ReferralsStorage storage s = _getStorage();

        uint256 maxReferrerFeeP = (_pairOpenFeeP * 2 * s.openFeeP) / 100;
        uint256 minFeeP = (maxReferrerFeeP * s.startReferrerFeeP) / 100;

        uint256 feeP = minFeeP +
            ((maxReferrerFeeP - minFeeP) * _volumeReferredUsd) /
            1e18 /
            s.targetVolumeUsd;

        return feeP > maxReferrerFeeP ? maxReferrerFeeP : feeP;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getTraderLastReferrer(address _trader) internal view returns (address) {
        return _getStorage().referrerByTrader[_trader];
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getTraderActiveReferrer(address _trader) internal view returns (address) {
        address referrer = getTraderLastReferrer(_trader);
        return getReferrerDetails(referrer).active ? referrer : address(0);
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferrersReferred(address _ally) internal view returns (address[] memory) {
        return getAllyDetails(_ally).referrersReferred;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getTradersReferred(address _referrer) internal view returns (address[] memory) {
        return getReferrerDetails(_referrer).tradersReferred;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferralsAllyFeeP() internal view returns (uint256) {
        return _getStorage().allyFeeP;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferralsStartReferrerFeeP() internal view returns (uint256) {
        return _getStorage().startReferrerFeeP;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferralsOpenFeeP() internal view returns (uint256) {
        return _getStorage().openFeeP;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferralsTargetVolumeUsd() internal view returns (uint256) {
        return _getStorage().targetVolumeUsd;
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getAllyDetails(
        address _ally
    ) internal view returns (IReferralsUtils.AllyDetails memory) {
        return _getStorage().allyDetails[_ally];
    }

    /**
     * @dev Check IReferralsUtils interface for documentation
     */
    function getReferrerDetails(
        address _referrer
    ) internal view returns (IReferralsUtils.ReferrerDetails memory) {
        return _getStorage().referrerDetails[_referrer];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_REFERRALS_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (IReferralsUtils.ReferralsStorage storage s) {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Whitelists new ally
     * @param _ally address of ally
     */
    function _whitelistAlly(address _ally) internal {
        if (_ally == address(0)) revert IGeneralErrors.ZeroAddress();

        IReferralsUtils.AllyDetails storage a = _getStorage().allyDetails[_ally];
        if (a.active) revert IReferralsUtils.AlreadyActive();

        a.active = true;

        emit IReferralsUtils.AllyWhitelisted(_ally);
    }

    /**
     * @dev Unwhitelists ally
     * @param _ally address of ally
     */
    function _unwhitelistAlly(address _ally) internal {
        IReferralsUtils.AllyDetails storage a = _getStorage().allyDetails[_ally];
        if (!a.active) revert IReferralsUtils.AlreadyInactive();

        a.active = false;

        emit IReferralsUtils.AllyUnwhitelisted(_ally);
    }

    /**
     * @dev Whitelists new referrer
     * @param _referrer address of referrer
     * @param _ally address of ally
     */
    function _whitelistReferrer(address _referrer, address _ally) internal {
        if (_referrer == address(0)) revert IGeneralErrors.ZeroAddress();
        IReferralsUtils.ReferralsStorage storage s = _getStorage();

        IReferralsUtils.ReferrerDetails storage r = s.referrerDetails[_referrer];
        if (r.active) revert IReferralsUtils.AlreadyActive();

        r.active = true;

        if (_ally != address(0)) {
            IReferralsUtils.AllyDetails storage a = s.allyDetails[_ally];
            if (!a.active) revert IReferralsUtils.AllyNotActive();

            r.ally = _ally;
            a.referrersReferred.push(_referrer);
        }

        emit IReferralsUtils.ReferrerWhitelisted(_referrer, _ally);
    }

    /**
     * @dev Unwhitelists referrer
     * @param _referrer address of referrer
     */
    function _unwhitelistReferrer(address _referrer) internal {
        IReferralsUtils.ReferrerDetails storage r = _getStorage().referrerDetails[_referrer];
        if (!r.active) revert IReferralsUtils.AlreadyInactive();

        r.active = false;

        emit IReferralsUtils.ReferrerUnwhitelisted(_referrer);
    }
}
