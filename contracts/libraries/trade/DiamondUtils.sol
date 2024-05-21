// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/trade/types/IDiamondStorage.sol";
import "./StorageUtils.sol";

/**
 * @custom:version 8
 *
 * @dev Diamond standard internal library to access storage
 */
library DiamondUtils {
    /**
     * @dev Returns storage slot for diamond data (facets, selectors, etc.)
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_DIAMOND_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (IDiamondStorage.DiamondStorage storage s) {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }
}
