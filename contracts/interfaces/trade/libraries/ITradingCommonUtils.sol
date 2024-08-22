// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @dev Interface for TradingCommonUtils library
 */
interface ITradingCommonUtils {
    /**
     *
     * @param trader address of the trader
     * @param collateralIndex index of the collateral
     * @param amountCollateral amount charged (collateral precision)
     */
    event GovFeeCharged(
        address indexed trader,
        uint8 indexed collateralIndex,
        uint256 amountCollateral
    );

    /**
     *
     * @param trader address of the trader
     * @param collateralIndex index of the collateral
     * @param amountCollateral amount charged (collateral precision)
     */
    event ReferralFeeCharged(
        address indexed trader,
        uint8 indexed collateralIndex,
        uint256 amountCollateral
    );

    /**
     *
     * @param trader address of the trader
     * @param collateralIndex index of the collateral
     * @param amountCollateral amount charged (collateral precision)
     */
    event GnsStakingFeeCharged(
        address indexed trader,
        uint8 indexed collateralIndex,
        uint256 amountCollateral
    );

    /**
     *
     * @param trader address of the trader
     * @param collateralIndex index of the collateral
     * @param amountCollateral amount charged (collateral precision)
     */
    event BorrowingProviderFeeCharged(
        address indexed trader,
        uint8 indexed collateralIndex,
        uint256 amountCollateral
    );

    /**
     *
     * @param trader address of the trader
     * @param collateralIndex index of the collateral
     * @param amountCollateral amount charged (collateral precision)
     */
    event RewardsFeeCharged(
        address indexed trader,
        uint8 indexed collateralIndex,
        uint256 amountCollateral
    );
}
