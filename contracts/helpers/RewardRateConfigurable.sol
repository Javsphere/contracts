// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract RewardRateConfigurable is Initializable {
    struct RewardsConfiguration {
        uint256 rewardPerBlock;
        uint256 lastUpdateBlockNum;
        uint256 updateBlocksInterval;
        uint128 block_multiplier;
        uint128 block_divider;
    }

    mapping(uint256 => RewardsConfiguration) private rewardsConfiguration;

    event RewardPerBlockUpdated(uint256 oldValue, uint256 newValue);

    function getRewardsConfiguration(
        uint256 _pid
    ) public view returns (RewardsConfiguration memory) {
        return rewardsConfiguration[_pid];
    }

    function getRewardPerBlock(uint256 _pid) public view returns (uint256) {
        return rewardsConfiguration[_pid].rewardPerBlock;
    }

    function _setRewardConfiguration(
        uint256 _pid,
        uint256 rewardPerBlock,
        uint256 updateBlocksInterval
    ) internal {
        uint256 oldRewardValue = rewardsConfiguration[_pid].rewardPerBlock;

        rewardsConfiguration[_pid] = RewardsConfiguration({
            rewardPerBlock: rewardPerBlock,
            lastUpdateBlockNum: block.number,
            updateBlocksInterval: updateBlocksInterval,
            block_multiplier: 1,
            block_divider: 1
        });

        emit RewardPerBlockUpdated(oldRewardValue, rewardPerBlock);
    }

    function _updateRewardPerBlock(uint256 _pid) internal {
        if (
            (block.number - rewardsConfiguration[_pid].lastUpdateBlockNum) <
            rewardsConfiguration[_pid].updateBlocksInterval
        ) {
            return;
        }

        uint256 rewardPerBlockOldValue = rewardsConfiguration[_pid].rewardPerBlock;

        rewardsConfiguration[_pid].rewardPerBlock =
            (rewardPerBlockOldValue * rewardsConfiguration[_pid].block_multiplier) /
            rewardsConfiguration[_pid].block_divider;

        rewardsConfiguration[_pid].lastUpdateBlockNum = block.number;

        emit RewardPerBlockUpdated(
            rewardPerBlockOldValue,
            rewardsConfiguration[_pid].rewardPerBlock
        );
    }
}
