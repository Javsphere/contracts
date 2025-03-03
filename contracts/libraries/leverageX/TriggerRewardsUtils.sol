// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/leverageX/IJavMultiCollatDiamond.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./StorageUtils.sol";
/**
 * @dev JavTriggerRewards facet internal library
 */
library TriggerRewardsUtils {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function addTrigger(address _triggerAddress) internal {
        ITriggerRewards.TriggerRewardsStorage storage s = _getStorage();
        require(!s.triggerAddresses.contains(_triggerAddress), IGeneralErrors.AlreadyExists());

        s.triggerAddresses.add(_triggerAddress);

        emit ITriggerRewardsUtils.TriggerAdded(_triggerAddress);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function removeTrigger(address _triggerAddress) internal {
        ITriggerRewards.TriggerRewardsStorage storage s = _getStorage();
        require(s.triggerAddresses.contains(_triggerAddress), IGeneralErrors.DoesntExist());

        s.triggerAddresses.remove(_triggerAddress);

        emit ITriggerRewardsUtils.TriggerRemoved(_triggerAddress);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function distributeTriggerReward(uint256 _rewards, uint8 _collateralIndex) internal {
        ITriggerRewards.TriggerRewardsStorage storage s = _getStorage();

        address[] memory triggers = s.triggerAddresses.values();
        uint256 rewardPerTrigger = _rewards / triggers.length;

        for (uint256 i; i < triggers.length; ++i) {
            s.pendingRewards[triggers[i]][_collateralIndex] += rewardPerTrigger;
        }

        emit ITriggerRewardsUtils.TriggerRewarded(
            _collateralIndex,
            rewardPerTrigger,
            triggers.length
        );
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function claimPendingTriggerRewards(uint8 _collateralIndex, address _triggerAddress) internal {
        ITriggerRewards.TriggerRewardsStorage storage s = _getStorage();

        uint256 pendingRewards = s.pendingRewards[_triggerAddress][_collateralIndex];
        require(pendingRewards != 0, ITriggerRewardsUtils.NoPendingTriggerRewards());

        s.pendingRewards[_triggerAddress][_collateralIndex];

        IERC20(_getMultiCollatDiamond().getCollateral(_collateralIndex).collateral).safeTransfer(
            _triggerAddress,
            pendingRewards
        );

        emit ITriggerRewardsUtils.TriggerRewardsClaimed(
            _triggerAddress,
            _collateralIndex,
            pendingRewards
        );
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function getTriggerPendingRewards(
        address _triggerAddress,
        uint8 _collateralIndex
    ) internal view returns (uint256) {
        return _getStorage().pendingRewards[_triggerAddress][_collateralIndex];
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function isValidTrigger(address _triggerAddress) internal view returns (bool) {
        return _getStorage().triggerAddresses.contains(_triggerAddress);
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRIGGER_REWARDS_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (ITriggerRewards.TriggerRewardsStorage storage s) {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IJavMultiCollatDiamond) {
        return IJavMultiCollatDiamond(address(this));
    }
}
