// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @dev Contains the types for the GNSTriggerRewards facet
 */
interface ITriggerRewards {

    struct TriggerRewardsStorage {
        EnumerableSet.AddressSet triggerAddresses;
        mapping(address => mapping(uint8 => uint256)) pendingRewards;
        uint256[48] __gap;
    }
}
