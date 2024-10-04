// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "../../interfaces/ITokenVesting.sol";
import "../../base/BaseUpgradable.sol";

contract Airdrop is BaseUpgradable {
    address public vestingAddress;

    /* ========== EVENTS ========== */
    event SetVestingAddress(address indexed _address);
    event DropVestingTokens(
        address indexed _recipient,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        bool _revocable,
        uint128 _amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _vesting) external initializer {
        vestingAddress = _vesting;

        __Base_init();
    }

    function setVestingAddress(address _address) external onlyAdmin {
        vestingAddress = _address;

        emit SetVestingAddress(_address);
    }

    /**
     * @notice Function to drop tokens with vesting
     * @param _recipients  recipients addresses
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration of a slice period for the vesting in seconds
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocable whether the vesting is revocable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     */
    function dropVestingTokens(
        address[] memory _recipients,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        bool _revocable,
        uint128 _amount,
        uint8 _vestingType,
        uint8 _lockId
    ) external onlyAdmin {
        ITokenVesting.InitialVestingSchedule[]
            memory vestingInfo = new ITokenVesting.InitialVestingSchedule[](_recipients.length);

        for (uint256 i = 0; i < _recipients.length; ++i) {
            vestingInfo[i] = ITokenVesting.InitialVestingSchedule({
                beneficiary: _recipients[i],
                start: _start,
                cliff: _cliff,
                duration: _duration,
                slicePeriodSeconds: _slicePeriodSeconds,
                revocable: _revocable,
                amount: _amount,
                vestingType: _vestingType,
                lockId: _lockId
            });
        }

        ITokenVesting(vestingAddress).createVestingScheduleBatch(vestingInfo);

        for (uint256 i = 0; i < vestingInfo.length; ++i) {
            emit DropVestingTokens(
                vestingInfo[i].beneficiary,
                vestingInfo[i].start,
                vestingInfo[i].cliff,
                vestingInfo[i].duration,
                vestingInfo[i].slicePeriodSeconds,
                vestingInfo[i].revocable,
                vestingInfo[i].amount
            );
        }
    }
}
