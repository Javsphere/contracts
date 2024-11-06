// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/helpers/ITokenLock.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IJavStakeX.sol";
import "../interfaces/IJavFreezer.sol";
import "../interfaces/IERC721Extended.sol";

contract BaseMigrator is IGeneralErrors, BaseUpgradable {
    using SafeERC20 for IERC20;

    /**
     * @dev MigrationInfo structure with signature
     * @param user address
     * @param tokenAmount token amount for wallet
     * @param stakingAmount token amount for staking
     * @param infinityPassTokenId infinitypass token id
     * @param infinityPassUri infinitypass token url
     * @param vestingSchedules vesting schedules info
     * @param vestingFreezerSchedules vesting freezer schedules info
     * @param freezerDeposits freezer schedules info
     * @param signature EIP712 secp256k1 signature
     */
    struct MigrationInfo {
        address user;
        uint256 tokenAmount;
        uint256 stakingAmount;
        uint256 infinityPassTokenId;
        string infinityPassUri;
        ITokenVesting.InitialVestingSchedule[] vestingSchedules;
        ITokenVesting.InitialVestingSchedule[] vestingFreezerSchedules;
        IJavFreezer.UserDeposit[] freezerDeposits;
    }

    IERC20 public token;
    address public vestingAddress;
    address public vestingFreezerAddress;
    address public stakingAddress;
    address public freezerAddress;
    address public infinityPass;
    address public signerAddress;

    mapping(bytes => bool) private signatureUsed;

    error AlreadyMigrated();
    error InvalidSigner();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address _vestingAddress,
        address _vestingFreezerAddress,
        address _stakingAddress,
        address _freezerAddress,
        address _infinityPass,
        address _signerAddress
    ) external initializer {
        token = IERC20(_tokenAddress);
        vestingAddress = _vestingAddress;
        vestingFreezerAddress = _vestingFreezerAddress;
        stakingAddress = _stakingAddress;
        freezerAddress = _freezerAddress;
        infinityPass = _infinityPass;
        signerAddress = _signerAddress;

        __Base_init();
    }

    function makeMigration(bytes calldata migrationData) external {
        require(migrationData.length >= 65, WrongLength()); // 65 bytes for the signature
        //        require(migrationInfo.signature.length == 65, WrongLength());
        bytes memory signature = _slice(migrationData, 0, 65);
        require(!signatureUsed[signature], AlreadyMigrated());

        bytes memory encodedData = _slice(migrationData, 65, migrationData.length - 65);
        address signer = _recover(keccak256(encodedData), signature);

        require(signer == signerAddress, InvalidSigner());
        signatureUsed[signature] = true;

        MigrationInfo memory migrationInfo = abi.decode(encodedData, (MigrationInfo));

        require(_msgSender() == migrationInfo.user, InvalidAddresses());

        //         vesting
        if (migrationInfo.vestingSchedules.length > 0) {
            uint256 totalAmount = 0;
            for (uint256 i = 0; i < migrationInfo.vestingSchedules.length; ++i) {
                totalAmount += migrationInfo.vestingSchedules[i].amount;
            }
            token.safeTransfer(vestingAddress, totalAmount);
            ITokenVesting(vestingAddress).createVestingScheduleBatch(
                migrationInfo.vestingSchedules
            );
        }

        // vesting freezer
        if (migrationInfo.vestingFreezerSchedules.length > 0) {
            uint256 totalAmount = 0;
            for (uint256 i = 0; i < migrationInfo.vestingFreezerSchedules.length; ++i) {
                totalAmount += migrationInfo.vestingFreezerSchedules[i].amount;
            }
            token.safeTransfer(freezerAddress, totalAmount);
            ITokenVesting(vestingFreezerAddress).createVestingScheduleBatch(
                migrationInfo.vestingFreezerSchedules
            );
        }

        // staking
        if (migrationInfo.stakingAmount > 0) {
            token.safeIncreaseAllowance(stakingAddress, migrationInfo.stakingAmount);
            IJavStakeX(stakingAddress).makeMigration(
                0,
                migrationInfo.stakingAmount,
                migrationInfo.user
            );
        }

        // freezer
        if (migrationInfo.freezerDeposits.length > 0) {
            uint256 totalAmount = 0;
            for (uint256 i = 0; i < migrationInfo.freezerDeposits.length; ++i) {
                totalAmount += migrationInfo.freezerDeposits[i].depositTokens;
            }
            token.safeIncreaseAllowance(freezerAddress, totalAmount);
            IJavFreezer(freezerAddress).makeMigration(
                0,
                migrationInfo.user,
                migrationInfo.freezerDeposits
            );
        }

        // infinity pass
        if (bytes(migrationInfo.infinityPassUri).length > 0) {
            IERC721Extended(infinityPass).makeMigration(
                migrationInfo.user,
                migrationInfo.infinityPassTokenId,
                migrationInfo.infinityPassUri
            );
        }

        if (migrationInfo.tokenAmount > 0) {
            token.safeTransfer(migrationInfo.user, migrationInfo.tokenAmount);
        }
    }

    function _slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) private pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    function _recover(bytes32 messageHash, bytes memory signature) private pure returns (address) {
        return ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
    }
}
