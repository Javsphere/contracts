// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/IJavFreezer.sol";
import "../interfaces/ITokenVesting.sol";

contract TokenVestingFreezer is ITokenVesting, BaseUpgradable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _allowedAddresses;

    address public freezer;
    uint256 public currentVestingId;
    uint256 public vestingSchedulesTotalAmount;
    mapping(bytes32 => VestingSchedule) public vestingSchedules;
    mapping(bytes32 => uint256) public vestingFreezeId;
    mapping(address => uint256) public holdersVestingCount;
    address public migratorAddress;

    /* ========== EVENTS ========== */
    event VestingScheduleAdded(
        address indexed beneficiary,
        uint256 cliff,
        uint256 start,
        uint256 duration,
        uint256 slicePeriodSeconds,
        uint256 amountTotal,
        bool revocable,
        uint8 vestingType
    );
    event SetFreezerAddress(address indexed _address);
    event Revoked(bytes32 indexed vestingScheduleId, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Released(bytes32 indexed vestingScheduleId, address indexed to, uint256 amount);
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);
    event SetMigratorAddress(address indexed _address);
    event BurnTokens(
        address indexed holder,
        bytes32 vestingScheduleId,
        uint256 freezerdepositID,
        uint256 amount
    );

    modifier onlyIfVestingScheduleNotRevoked(bytes32 _vestingScheduleId) {
        require(vestingSchedules[_vestingScheduleId].initialized);
        require(!vestingSchedules[_vestingScheduleId].revoked);
        _;
    }

    modifier onlyAllowedAddresses() {
        require(_allowedAddresses.contains(msg.sender), "TokenVesting: only allowed addresses");
        _;
    }

    modifier onlyMigrator() {
        require(msg.sender == migratorAddress, "TokenVesting: only migrator addresses");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _freezerAddress) external initializer {
        currentVestingId = 1;
        freezer = _freezerAddress;

        _allowedAddresses.add(msg.sender);

        __Base_init();
        __ReentrancyGuard_init();
    }

    function setFreezerAddress(address _address) external onlyAdmin {
        freezer = _address;

        emit SetFreezerAddress(_address);
    }

    function addAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.add(_address);

        emit AddAllowedAddress(_address);
    }

    function removeAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.remove(_address);

        emit RemoveAllowedAddress(_address);
    }

    function setMigratorAddress(address _address) external onlyAdmin {
        migratorAddress = _address;

        emit SetMigratorAddress(_address);
    }

    /**
     * @notice Creates a new vesting schedule
     * @param _beneficiary  beneficiary
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration of a slice period for the vesting in seconds
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocable whether the vesting is revocable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     * @param _vestingType vesting type, use only on front end side
     */
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
    ) external onlyAllowedAddresses {
        _createVestingSchedule(
            _beneficiary,
            _start,
            _cliff,
            _duration,
            _slicePeriodSeconds,
            _revocable,
            _amount,
            _vestingType,
            _lockId
        );
    }

    /**
     * @notice Creates a new vesting schedules
     * @param _vestingInfo array of vesting information
     */
    function createVestingScheduleBatch(
        InitialVestingSchedule[] memory _vestingInfo
    ) external onlyAllowedAddresses {
        for (uint256 i = 0; i < _vestingInfo.length; ++i) {
            _createVestingSchedule(
                _vestingInfo[i].beneficiary,
                _vestingInfo[i].start,
                _vestingInfo[i].cliff,
                _vestingInfo[i].duration,
                _vestingInfo[i].slicePeriodSeconds,
                _vestingInfo[i].revocable,
                _vestingInfo[i].amount,
                _vestingInfo[i].vestingType,
                _vestingInfo[i].lockId
            );
        }
    }

    /**
     * @notice Revokes the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(
        bytes32 vestingScheduleId
    ) external onlyAdmin onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.revocable, "TokenVesting: vesting is not revocable");
        uint128 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount > 0) {
            _release(msg.sender, vestingScheduleId);
        }
        uint256 unreleased = vestingSchedule.amountTotal - vestingSchedule.released;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - unreleased;
        vestingSchedule.revoked = true;

        emit Revoked(vestingScheduleId, vestedAmount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function release(
        bytes32 vestingScheduleId
    ) external whenNotPaused nonReentrant onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        _release(msg.sender, vestingScheduleId);
    }

    /**
     * @notice Function to get allowed addresses
     */
    function getAllowedAddresses() external view returns (address[] memory) {
        return _allowedAddresses.values();
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index
    ) external view returns (VestingSchedule memory) {
        bytes32 vestingScheduleId = _computeVestingScheduleIdForAddressAndIndex(holder, index);
        return vestingSchedules[vestingScheduleId];
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(
        bytes32 vestingScheduleId
    ) external view onlyIfVestingScheduleNotRevoked(vestingScheduleId) returns (uint256) {
        VestingSchedule memory vestingSchedule = vestingSchedules[vestingScheduleId];
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        uint256 freezeProfit = IJavFreezer(freezer).pendingReward(
            0,
            vestingFreezeId[vestingScheduleId],
            vestingSchedule.beneficiary
        );
        return vestedAmount + freezeProfit;
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address.
     */
    function getLastVestingScheduleForHolder(
        address holder
    ) external view returns (VestingSchedule memory) {
        return
            vestingSchedules[
                _computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder] - 1)
            ];
    }

    function burnTokens(address _holder) external onlyMigrator {
        bytes32 _vestingScheduleId;
        for (uint256 i = 0; i < holdersVestingCount[_holder]; ++i) {
            _vestingScheduleId = _computeVestingScheduleIdForAddressAndIndex(_holder, i);
            if (_computeReleasableAmount(vestingSchedules[_vestingScheduleId]) > 0) {
                _release(_holder, _vestingScheduleId);
            }
            VestingSchedule storage vestingSchedule = vestingSchedules[_vestingScheduleId];
            if (!vestingSchedule.revoked) {
                uint256 unreleased = vestingSchedule.amountTotal - vestingSchedule.released;
                vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - unreleased;
                vestingSchedule.revoked = true;

                emit BurnTokens(
                    _holder,
                    _vestingScheduleId,
                    vestingFreezeId[_vestingScheduleId],
                    unreleased
                );
            }
        }
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(
        address holder,
        uint256 index
    ) external pure returns (bytes32) {
        return _computeVestingScheduleIdForAddressAndIndex(holder, index);
    }

    function _createVestingSchedule(
        address _beneficiary,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        bool _revocable,
        uint128 _amount,
        uint8 _vestingType,
        uint256 _lockId
    ) private {
        require(_duration > 0, "TokenVesting: duration must be > 0");
        require(_amount > 0, "TokenVesting: amount must be > 0");
        require(_slicePeriodSeconds > 0, "TokenVesting: slicePeriodSeconds must be > 0");
        require(_duration >= _cliff, "TokenVesting: duration must be >= cliff");
        bytes32 vestingScheduleId = _computeVestingScheduleIdForAddressAndIndex(
            _beneficiary,
            holdersVestingCount[_beneficiary]
        );
        uint128 cliff = _start + _cliff;
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            _beneficiary,
            cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _revocable,
            _amount,
            0,
            false,
            _vestingType
        );
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount + _amount;
        currentVestingId++;
        holdersVestingCount[_beneficiary] += 1;
        uint256 withdrawalTimestamp = _start + _duration;

        IJavFreezer(freezer).depositVesting(
            _beneficiary,
            0,
            _amount,
            cliff,
            withdrawalTimestamp,
            _lockId
        );
        uint256 freezeId = IJavFreezer(freezer).getUserLastDepositId(0, _beneficiary);

        vestingFreezeId[vestingScheduleId] = freezeId;

        emit VestingScheduleAdded(
            _beneficiary,
            cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _amount,
            _revocable,
            _vestingType
        );
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function _release(address holder, bytes32 vestingScheduleId) private {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = holder == vestingSchedule.beneficiary;
        bool isReleasor = holder == owner();

        require(
            isBeneficiary || isReleasor,
            "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        uint128 releasableAmount = _computeReleasableAmount(vestingSchedule);
        require(releasableAmount > 0, "TokenVesting: invalid releasable amount");

        IJavFreezer(freezer).withdrawVesting(
            vestingSchedule.beneficiary,
            0,
            vestingFreezeId[vestingScheduleId],
            releasableAmount
        );

        vestingSchedule.released = vestingSchedule.released + releasableAmount;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - releasableAmount;

        emit Released(vestingScheduleId, vestingSchedule.beneficiary, releasableAmount);
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function _computeVestingScheduleIdForAddressAndIndex(
        address holder,
        uint256 index
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(
        VestingSchedule memory vestingSchedule
    ) private view returns (uint128) {
        // Retrieve the current time.
        uint256 currentTime = block.timestamp;
        // If the current time is before the cliff, no tokens are releasable.
        if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked) {
            return 0;
        }
        // If the current time is after the vesting period, all tokens are releasable,
        // minus the amount already released.
        else if (currentTime >= vestingSchedule.start + vestingSchedule.duration) {
            return vestingSchedule.amountTotal - vestingSchedule.released;
        }
        // Otherwise, some tokens are releasable.
        else {
            // Compute the number of full vesting periods that have elapsed.
            uint256 timeFromStart = currentTime - vestingSchedule.start;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;
            // Compute the amount of tokens that are vested.
            uint128 vestedAmount = uint128(
                (vestingSchedule.amountTotal * vestedSeconds) / vestingSchedule.duration
            );
            // Subtract the amount already released and return.
            return vestedAmount - vestingSchedule.released;
        }
    }
}
