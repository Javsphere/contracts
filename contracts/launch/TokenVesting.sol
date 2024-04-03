// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/ITokenVesting.sol";

contract TokenVesting is ITokenVesting, BaseUpgradable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

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

    EnumerableSet.AddressSet private _allowedAddresses;

    IERC20 public token;
    uint256 public currentVestingId;
    uint256 public vestingSchedulesTotalAmount;
    mapping(bytes32 => VestingSchedule) public vestingSchedules;
    mapping(address => uint256) public holdersVestingCount;

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
    event Revoked(bytes32 indexed vestingScheduleId, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Released(bytes32 indexed vestingScheduleId, address indexed to, uint256 amount);
    event AddAllowedAddress(address indexed _address);
    event RemoveAllowedAddress(address indexed _address);

    modifier onlyIfVestingScheduleNotRevoked(bytes32 _vestingScheduleId) {
        require(vestingSchedules[_vestingScheduleId].initialized);
        require(!vestingSchedules[_vestingScheduleId].revoked);
        _;
    }

    modifier onlyAllowedAddresses(address _sender) {
        require(_allowedAddresses.contains(_sender), "TokenVesting: only allowed addresses");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token) external initializer {
        token = IERC20(_token);
        currentVestingId = 1;

        _allowedAddresses.add(msg.sender);

        __Base_init();
        __ReentrancyGuard_init();
    }

    function addAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.add(_address);

        emit AddAllowedAddress(_address);
    }

    function removeAllowedAddress(address _address) external onlyAdmin {
        _allowedAddresses.remove(_address);

        emit RemoveAllowedAddress(_address);
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
    ) external onlyAllowedAddresses(msg.sender) {
        _createVestingSchedule(
            _beneficiary,
            _start,
            _cliff,
            _duration,
            _slicePeriodSeconds,
            _revocable,
            _amount,
            _vestingType
        );
    }

    /**
     * @notice Creates a new vesting schedules
     * @param _vestingInfo array of vesting information
     */
    function createVestingScheduleBatch(
        InitialVestingSchedule[] memory _vestingInfo
    ) external onlyAllowedAddresses(msg.sender) {
        for (uint256 i = 0; i < _vestingInfo.length; ++i) {
            _createVestingSchedule(
                _vestingInfo[i].beneficiary,
                _vestingInfo[i].start,
                _vestingInfo[i].cliff,
                _vestingInfo[i].duration,
                _vestingInfo[i].slicePeriodSeconds,
                _vestingInfo[i].revocable,
                _vestingInfo[i].amount,
                _vestingInfo[i].vestingType
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
            _release(vestingScheduleId);
        }
        uint256 unreleased = vestingSchedule.amountTotal - vestingSchedule.released;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - unreleased;
        vestingSchedule.revoked = true;

        emit Revoked(vestingScheduleId, vestedAmount);
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(address to, uint256 amount) external nonReentrant onlyAdmin {
        require(getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");

        token.safeTransfer(to, amount);

        emit Withdraw(to, amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function release(
        bytes32 vestingScheduleId
    ) external whenNotPaused nonReentrant onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        _release(vestingScheduleId);
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
        return _computeReleasableAmount(vestingSchedule);
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

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(
        address holder,
        uint256 index
    ) external pure returns (bytes32) {
        return _computeVestingScheduleIdForAddressAndIndex(holder, index);
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the multisign wallet.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return token.balanceOf(address(this)) - vestingSchedulesTotalAmount;
    }

    function _createVestingSchedule(
        address _beneficiary,
        uint128 _start,
        uint128 _cliff,
        uint128 _duration,
        uint128 _slicePeriodSeconds,
        bool _revocable,
        uint128 _amount,
        uint8 _vestingType
    ) private {
        require(
            getWithdrawableAmount() >= _amount,
            "TokenVesting: cannot create vesting schedule because not sufficient tokens"
        );
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
    function _release(bytes32 vestingScheduleId) private {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isReleasor = msg.sender == owner();

        require(
            isBeneficiary || isReleasor,
            "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        uint128 releasableAmount = _computeReleasableAmount(vestingSchedule);

        require(releasableAmount > 0, "TokenVesting: invalid releasable amount");

        vestingSchedule.released = vestingSchedule.released + releasableAmount;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - releasableAmount;

        token.safeTransfer(vestingSchedule.beneficiary, releasableAmount);

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
