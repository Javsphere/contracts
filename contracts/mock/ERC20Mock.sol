// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//
contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) payable ERC20(name, symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(uint256 value) external {
        _burn(_msgSender(), value);
    }
}
