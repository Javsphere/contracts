// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../types/ITriggerRewards.sol";

interface ITriggerRewardsUtils is ITriggerRewards {
    /**
     *
     * @dev Add trigger for triggers addresses
     * @param _triggerAddress trigger address
     */
    function addTrigger(address _triggerAddress) external;

    /**
     *
     * @dev Remove trigger from trigger addresses
     * @param _triggerAddress trigger address
     */
    function removeTrigger(address _triggerAddress) external;

    /**
     *
     * @dev Distributes rewards to oracles for a specific trigger
     * @param _rewards total reward to be distributed among triggers
     * @param _collateralIndex collateral index
     */
    function distributeTriggerReward(uint256 _rewards, uint8 _collateralIndex) external;

    /**
     * @dev Claims pending trigger rewards
     * @param _collateralIndex collateral index
     */
    function claimPendingTriggerRewards(uint8 _collateralIndex) external;

    /**
     *
     * @dev Returns the pending trigger rewards for an trigger
     * @param _triggerAddress address of the trigger
     * @param _collateralIndex collateral index
     */
    function getTriggerPendingRewards(
        address _triggerAddress,
        uint8 _collateralIndex
    ) external view returns (uint256);

    /**
     *
     * @dev Checks if trigger address register
     * @param _triggerAddress trigger address
     */
    function isValidTrigger(address _triggerAddress) external view returns (bool);

    /**
     *
     * @dev Emitted when added trigger
     * @param triggerAddress trigger address
     */
    event TriggerAdded(address triggerAddress);

    /**
     *
     * @dev Emitted when remove trigger
     * @param triggerAddress trigger address
     */
    event TriggerRemoved(address triggerAddress);

    /**
     *
     * @dev Emitted when trigger rewards are distributed for a specific order
     * @param collateralIndex collateral index
     * @param rewardsPerTrigger reward in collateral distributed per trigger
     * @param triggersCount number of triggers rewarded
     */
    event TriggerRewarded(uint8 collateralIndex, uint256 rewardsPerTrigger, uint256 triggersCount);

    /**
     *
     * @dev Emitted when pending trigger rewards are claimed by an trigger
     * @param trigger address of the oracle
     * @param collateralIndex collateralIndex
     * @param rewards rewards claimed
     */
    event TriggerRewardsClaimed(address trigger, uint8 collateralIndex, uint256 rewards);

    error NoPendingTriggerRewards();
}
