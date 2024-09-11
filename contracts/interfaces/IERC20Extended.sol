// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);

    function mint(address account, uint256 amount) external;

    function burn(uint256 value) external;

    function burnFrom(address account, uint256 value) external;
}
