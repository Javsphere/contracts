// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ITokenVesting {
    struct InitialVestingSchedule {
        // address of the beneficiary to whom vested tokens are transferred
        address beneficiary;
        // start time of the vesting period
        uint128 start;
        // duration in seconds of the cliff in which tokens will begin to vest
        uint128 cliff;
        // duration in seconds of the period in which the tokens will vest
        uint128 duration;
        // duration of a slice period for the vesting in seconds
        uint128 slicePeriodSeconds;
        // whether the vesting is revocable or not
        bool revocable;
        // total amount of tokens to be released at the end of the vesting
        uint128 amount;
        // vesting type
        uint8 vestingType;
        // lock id (use only for freezer
        uint8 lockId;
    }

    struct VestingSchedule {
        bool initialized;
        // beneficiary of tokens after they are released
        address beneficiary;
        // cliff period in seconds
        uint128 cliff;
        // start time of the vesting period
        uint128 start;
        // duration of the vesting period in seconds
        uint128 duration;
        // duration of a slice period for the vesting in seconds
        uint128 slicePeriodSeconds;
        // whether or not the vesting is revocable
        bool revocable;
        // total amount of tokens to be released at the end of the vesting
        uint128 amountTotal;
        // amount of tokens released
        uint128 released;
        // whether or not the vesting has been revoked
        bool revoked;
        // vesting type
        uint8 vestingType;
    }

    function createVestingScheduleBatch(InitialVestingSchedule[] memory _vestingInfo) external;

    function createVestingSchedule(
        address _beneficiary,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        bool _revocable,
        uint128 _amount,
        uint8 _vestingType,
        uint256 _lockId
    ) external;

    function holdersVestingCount(address holder) external view returns (uint256);

    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index
    ) external view returns (VestingSchedule memory);

    function burnTokens(address _holder) external;
}
