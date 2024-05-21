// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/trade/IJavMultiCollatDiamond.sol";
import "../../interfaces/IERC20Extended.sol";

import "./AddressStoreUtils.sol";
import "./StorageUtils.sol";

/**
 * @custom:version 8
 * @dev GNSTriggerRewards facet internal library
 */

interface IChainlinkOracle {
    function getAuthorizationStatus(address) external view returns (bool);

    function owner() external view returns (address);
}

library TriggerRewardsUtils {
    using SafeERC20 for IERC20;

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function initializeTriggerRewards(uint16 _timeoutBlocks) internal {
        updateTriggerTimeoutBlocks(_timeoutBlocks);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function updateTriggerTimeoutBlocks(uint16 _timeoutBlocks) internal {
        if (_timeoutBlocks == 0) revert ITriggerRewardsUtils.TimeoutBlocksZero();

        _getStorage().triggerTimeoutBlocks = _timeoutBlocks;

        emit ITriggerRewardsUtils.TriggerTimeoutBlocksUpdated(_timeoutBlocks);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function distributeTriggerReward(uint256 _rewardGns) internal {
        ITriggerRewards.TriggerRewardsStorage storage s = _getStorage();

        address[] memory oracles = _getMultiCollatDiamond().getOracles();
        uint256 rewardPerOracleGns = _rewardGns / oracles.length;

        for (uint256 i; i < oracles.length; ++i) {
            s.pendingRewardsGns[oracles[i]] += rewardPerOracleGns;
        }

        IERC20Extended(AddressStoreUtils.getAddresses().gns).mint(address(this), _rewardGns);

        emit ITriggerRewardsUtils.TriggerRewarded(rewardPerOracleGns, oracles.length);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function claimPendingTriggerRewards(address _oracle) internal {
        ITriggerRewards.TriggerRewardsStorage storage s = _getStorage();

        IChainlinkOracle oracle = IChainlinkOracle(_oracle);
        if (oracle.owner() != msg.sender && !oracle.getAuthorizationStatus(msg.sender))
            revert IGeneralErrors.NotAuthorized();

        uint256 pendingRewardsGns = s.pendingRewardsGns[_oracle];
        if (pendingRewardsGns == 0) revert ITriggerRewardsUtils.NoPendingTriggerRewards();

        s.pendingRewardsGns[_oracle] = 0;
        IERC20(AddressStoreUtils.getAddresses().gns).safeTransfer(msg.sender, pendingRewardsGns);

        emit ITriggerRewardsUtils.TriggerRewardsClaimed(_oracle, pendingRewardsGns);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function getTriggerTimeoutBlocks() internal view returns (uint16) {
        return _getStorage().triggerTimeoutBlocks;
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function hasActiveOrder(
        uint256 _orderBlock,
        uint256 _currentBlock
    ) internal view returns (bool) {
        return _currentBlock - _orderBlock < uint256(_getStorage().triggerTimeoutBlocks);
    }

    /**
     * @dev Check ITriggerRewardsUtils interface for documentation
     */
    function getTriggerPendingRewardsGns(address _oracle) internal view returns (uint256) {
        return _getStorage().pendingRewardsGns[_oracle];
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
