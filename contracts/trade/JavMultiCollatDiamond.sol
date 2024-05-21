// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../interfaces/trade/IJavDiamond.sol";
import "./abstract/JavAddressStore.sol";
import "./abstract/JavDiamondStorage.sol";
import "./abstract/JavDiamondCut.sol";
import "./abstract/JavDiamondLoupe.sol";

/**
 * @custom:version 8
 * @dev Diamond that contains all code for the gTrade leverage trading platform
 */
contract JavMultiCollatDiamond is
    JavAddressStore, // base: Initializable + global storage, always first
    JavDiamondStorage, // storage for each facet
    JavDiamondCut, // diamond management
    JavDiamondLoupe, // diamond getters
    IJavDiamond // diamond interface (types only), always last
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
}
