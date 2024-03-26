// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IJavFreezer {
    function depositVesting(
        address _holder,
        uint256 _pid,
        uint256 _amount,
        uint256 _depositTimestamp,
        uint256 _withdrawalTimestamp,
        uint256 _lockId
    ) external;

    function withdrawVesting(
        address _holder,
        uint256 _pid,
        uint256 _depositId,
        uint256 _amount
    ) external;

    function pendingReward(
        uint256 _pid,
        uint256 _depositId,
        address _user
    ) external view returns (uint256);

    function getUserLastDepositId(uint256 _pid, address _user) external view returns (uint256);
}
