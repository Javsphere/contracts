// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "./IJavAddressStore.sol";
import "./IJavDiamondCut.sol";
import "./IJavDiamondLoupe.sol";
import "./types/ITypes.sol";

/**
 * @custom:version 8
 * @dev the non-expanded interface for multi-collat diamond, only contains types/structs/enums
 */

interface IJavDiamond is IJavAddressStore, IJavDiamondCut, IJavDiamondLoupe, ITypes {

}
