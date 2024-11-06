// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//
contract ERC20Mock is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals_
    ) payable ERC20(name, symbol) {
        _decimals = _decimals_;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(uint256 value) external {
        _burn(_msgSender(), value);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
