// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./access/MultiSignatureUpgradeable.sol";

contract TokenVesting is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    MultiSignatureUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant WITHDRAW = keccak256("WITHDRAW");

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
    }

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
    }

    IERC20 public token;
    address public adminAddress;
    uint256 public currentVestingId;
    uint256 public vestingSchedulesTotalAmount;
    mapping(bytes32 => VestingSchedule) public vestingSchedules;
    mapping(address => uint256) public holdersVestingCount;

    /* ========== EVENTS ========== */
    event Initialized(address indexed executor, uint256 at);
    event SetAdminAddress(address indexed _address);
    event VestingScheduleAdded(
        address indexed beneficiary,
        uint256 cliff,
        uint256 start,
        uint256 duration,
        uint256 slicePeriodSeconds,
        uint256 amountTotal,
        bool revocable
    );
    event Revoked(bytes32 indexed vestingScheduleId, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Released(bytes32 indexed vestingScheduleId, address indexed to, uint256 amount);

    modifier onlyIfVestingScheduleNotRevoked(bytes32 _vestingScheduleId) {
        require(vestingSchedules[_vestingScheduleId].initialized);
        require(!vestingSchedules[_vestingScheduleId].revoked);
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress || msg.sender == owner(), "TokenVesting: only admin");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _token,
        uint256 _minimumSignatures,
        address[] memory _signers
    ) external initializer {
        adminAddress = msg.sender;
        token = IERC20(_token);
        currentVestingId = 1;

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __MultiSignatureUpgradeable_init(_minimumSignatures, _signers);

        emit Initialized(msg.sender, block.number);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function setAdminAddress(address _address) external onlyAdmin {
        adminAddress = _address;

        emit SetAdminAddress(_address);
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _vestingInfo array of vesting information
     */
    function createVestingSchedules(
        InitialVestingSchedule[] memory _vestingInfo
    ) external onlyAdmin {
        for (uint256 i = 0; i < _vestingInfo.length; ++i) {
            require(
                getWithdrawableAmount() >= _vestingInfo[i].amount,
                "TokenVesting: cannot create vesting schedule because not sufficient tokens"
            );
            require(_vestingInfo[i].duration > 0, "TokenVesting: duration must be > 0");
            require(_vestingInfo[i].amount > 0, "TokenVesting: amount must be > 0");
            require(
                _vestingInfo[i].slicePeriodSeconds > 0,
                "TokenVesting: slicePeriodSeconds must be > 0"
            );
            require(
                _vestingInfo[i].duration >= _vestingInfo[i].cliff,
                "TokenVesting: duration must be >= cliff"
            );
            bytes32 vestingScheduleId = _computeVestingScheduleIdForAddressAndIndex(
                _vestingInfo[i].beneficiary,
                holdersVestingCount[_vestingInfo[i].beneficiary]
            );
            uint128 cliff = _vestingInfo[i].start + _vestingInfo[i].cliff;
            vestingSchedules[vestingScheduleId] = VestingSchedule(
                true,
                _vestingInfo[i].beneficiary,
                cliff,
                _vestingInfo[i].start,
                _vestingInfo[i].duration,
                _vestingInfo[i].slicePeriodSeconds,
                _vestingInfo[i].revocable,
                _vestingInfo[i].amount,
                0,
                false
            );
            vestingSchedulesTotalAmount = vestingSchedulesTotalAmount + _vestingInfo[i].amount;
            currentVestingId++;
            holdersVestingCount[_vestingInfo[i].beneficiary] += 1;

            emit VestingScheduleAdded(
                _vestingInfo[i].beneficiary,
                cliff,
                _vestingInfo[i].start,
                _vestingInfo[i].duration,
                _vestingInfo[i].slicePeriodSeconds,
                _vestingInfo[i].amount,
                _vestingInfo[i].revocable
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
            _release(vestingScheduleId, vestedAmount);
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
    function withdraw(uint256 amount) external nonReentrant onlyAdmin needAction(WITHDRAW) {
        require(getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");

        token.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function release(
        bytes32 vestingScheduleId,
        uint128 amount
    ) external whenNotPaused nonReentrant onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        _release(vestingScheduleId, amount);
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
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view onlyAdmin returns (uint256) {
        return token.balanceOf(address(this)) - vestingSchedulesTotalAmount;
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function _release(bytes32 vestingScheduleId, uint128 amount) private {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isReleasor = msg.sender == owner();

        require(
            isBeneficiary || isReleasor,
            "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(
            vestedAmount >= amount,
            "TokenVesting: cannot release tokens, not enough vested tokens"
        );
        vestingSchedule.released = vestingSchedule.released + amount;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - amount;

        token.safeTransfer(vestingSchedule.beneficiary, amount);

        emit Released(vestingScheduleId, vestingSchedule.beneficiary, amount);
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[43] private ____gap;
}
