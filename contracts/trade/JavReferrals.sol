// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/libraries/IReferralsUtils.sol";
import "../libraries/trade/ReferralsUtils.sol";
import "./abstract/JavAddressStore.sol";

/**
 * @custom:version 8
 * @dev Facet #2: Referral system
 */
contract JavReferrals is JavAddressStore, IReferralsUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IReferralsUtils
    function initializeReferrals(
        uint256 _allyFeeP,
        uint256 _startReferrerFeeP,
        uint256 _openFeeP,
        uint256 _targetVolumeUsd
    ) external reinitializer(2) {
        ReferralsUtils.initializeReferrals(
            _allyFeeP,
            _startReferrerFeeP,
            _openFeeP,
            _targetVolumeUsd
        );
    }

    // Management Setters

    /// @inheritdoc IReferralsUtils
    function updateAllyFeeP(uint256 _value) external onlyRole(Role.GOV) {
        ReferralsUtils.updateAllyFeeP(_value);
    }

    /// @inheritdoc IReferralsUtils
    function updateStartReferrerFeeP(uint256 _value) external onlyRole(Role.GOV) {
        ReferralsUtils.updateStartReferrerFeeP(_value);
    }

    /// @inheritdoc IReferralsUtils
    function updateReferralsOpenFeeP(uint256 _value) external onlyRole(Role.GOV) {
        ReferralsUtils.updateReferralsOpenFeeP(_value);
    }

    /// @inheritdoc IReferralsUtils
    function updateReferralsTargetVolumeUsd(uint256 _value) external onlyRole(Role.GOV) {
        ReferralsUtils.updateReferralsTargetVolumeUsd(_value);
    }

    /// @inheritdoc IReferralsUtils
    function whitelistAllies(address[] calldata _allies) external onlyRole(Role.GOV) {
        ReferralsUtils.whitelistAllies(_allies);
    }

    /// @inheritdoc IReferralsUtils
    function unwhitelistAllies(address[] calldata _allies) external onlyRole(Role.GOV) {
        ReferralsUtils.unwhitelistAllies(_allies);
    }

    /// @inheritdoc IReferralsUtils
    function whitelistReferrers(
        address[] calldata _referrers,
        address[] calldata _allies
    ) external onlyRole(Role.GOV) {
        ReferralsUtils.whitelistReferrers(_referrers, _allies);
    }

    /// @inheritdoc IReferralsUtils
    function unwhitelistReferrers(address[] calldata _referrers) external onlyRole(Role.GOV) {
        ReferralsUtils.unwhitelistReferrers(_referrers);
    }

    // Interactions

    /// @inheritdoc IReferralsUtils
    function registerPotentialReferrer(
        address _trader,
        address _referrer
    ) external virtual onlySelf {
        ReferralsUtils.registerPotentialReferrer(_trader, _referrer);
    }

    /// @inheritdoc IReferralsUtils
    function distributeReferralReward(
        address _trader,
        uint256 _volumeUsd,
        uint256 _pairOpenFeeP,
        uint256 _javPriceUsd
    ) external virtual onlySelf returns (uint256) {
        return
            ReferralsUtils.distributeReferralReward(
                _trader,
                _volumeUsd,
                _pairOpenFeeP,
                _javPriceUsd
            );
    }

    /// @inheritdoc IReferralsUtils
    function claimAllyRewards() external {
        ReferralsUtils.claimAllyRewards();
    }

    /// @inheritdoc IReferralsUtils
    function claimReferrerRewards() external {
        ReferralsUtils.claimReferrerRewards();
    }

    // Getters

    /// @inheritdoc IReferralsUtils
    function getReferrerFeeP(
        uint256 _pairOpenFeeP,
        uint256 _volumeReferredUsd
    ) external view returns (uint256) {
        return ReferralsUtils.getReferrerFeeP(_pairOpenFeeP, _volumeReferredUsd);
    }

    /// @inheritdoc IReferralsUtils
    function getTraderLastReferrer(address _trader) external view returns (address) {
        return ReferralsUtils.getTraderLastReferrer(_trader);
    }

    /// @inheritdoc IReferralsUtils
    function getTraderActiveReferrer(address _trader) external view returns (address) {
        return ReferralsUtils.getTraderActiveReferrer(_trader);
    }

    /// @inheritdoc IReferralsUtils
    function getReferrersReferred(address _ally) external view returns (address[] memory) {
        return ReferralsUtils.getReferrersReferred(_ally);
    }

    /// @inheritdoc IReferralsUtils
    function getTradersReferred(address _referrer) external view returns (address[] memory) {
        return ReferralsUtils.getTradersReferred(_referrer);
    }

    /// @inheritdoc IReferralsUtils
    function getReferralsAllyFeeP() external view returns (uint256) {
        return ReferralsUtils.getReferralsAllyFeeP();
    }

    /// @inheritdoc IReferralsUtils
    function getReferralsStartReferrerFeeP() external view returns (uint256) {
        return ReferralsUtils.getReferralsStartReferrerFeeP();
    }

    /// @inheritdoc IReferralsUtils
    function getReferralsOpenFeeP() external view returns (uint256) {
        return ReferralsUtils.getReferralsOpenFeeP();
    }

    /// @inheritdoc IReferralsUtils
    function getReferralsTargetVolumeUsd() external view returns (uint256) {
        return ReferralsUtils.getReferralsTargetVolumeUsd();
    }

    /// @inheritdoc IReferralsUtils
    function getAllyDetails(address _ally) external view returns (AllyDetails memory) {
        return ReferralsUtils.getAllyDetails(_ally);
    }

    /// @inheritdoc IReferralsUtils
    function getReferrerDetails(address _referrer) external view returns (ReferrerDetails memory) {
        return ReferralsUtils.getReferrerDetails(_referrer);
    }
}
