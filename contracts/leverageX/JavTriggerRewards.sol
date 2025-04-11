// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./abstract/JavAddressStore.sol";
import "../interfaces/leverageX/libraries/ITriggerRewardsUtils.sol";
import "../libraries/leverageX/TriggerRewardsUtils.sol";

/**
 * @dev Facet #6: Trigger rewards
 */
contract JavTriggerRewards is JavAddressStore, ITriggerRewardsUtils {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Management Setters

    /// @inheritdoc ITriggerRewardsUtils
    function addTrigger(address _triggerAddress) external onlyRole(Role.GOV) {
        TriggerRewardsUtils.addTrigger(_triggerAddress);
    }

    /// @inheritdoc ITriggerRewardsUtils
    function removeTrigger(address _triggerAddress) external onlyRole(Role.GOV) {
        TriggerRewardsUtils.removeTrigger(_triggerAddress);
    }

    // Interactions

    /// @inheritdoc ITriggerRewardsUtils
    function distributeTriggerReward(
        uint256 _rewards,
        uint8 _collateralIndex
    ) external virtual onlySelf {
        TriggerRewardsUtils.distributeTriggerReward(_rewards, _collateralIndex);
    }

    /// @inheritdoc ITriggerRewardsUtils
    function claimPendingTriggerRewards(uint8 _collateralIndex) external {
        TriggerRewardsUtils.claimPendingTriggerRewards(_collateralIndex, _msgSender()); // access control in library
    }

    // Getters
    /// @inheritdoc ITriggerRewardsUtils
    function getTriggerPendingRewards(
        address _triggerAddress,
        uint8 _collateralIndex
    ) external view returns (uint256) {
        return TriggerRewardsUtils.getTriggerPendingRewards(_triggerAddress, _collateralIndex);
    }

    /// @inheritdoc ITriggerRewardsUtils
    function isValidTrigger(address _triggerAddress) external view returns (bool) {
        return TriggerRewardsUtils.isValidTrigger(_triggerAddress);
    }
}
