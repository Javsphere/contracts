// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

interface IPriceUtils {
    /// @notice Converts a price to a uint256 with a target number of decimals
    /// @param price The price
    /// @param expo The price exponent
    /// @param targetDecimals The target number of decimals
    /// @return The price as a uint256
    /// @dev Function will lose precision if targetDecimals is less than the Pyth price decimals.
    /// This method will truncate any digits that cannot be represented by the targetDecimals.
    /// e.g. If the price is 0.000123 and the targetDecimals is 2, the result will be 0
    function convertToUint(
        int64 price,
        int32 expo,
        uint8 targetDecimals
    ) external pure returns (uint256);
}
