// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IVanillaRouter02.sol";
import "../base/BaseUpgradable.sol";

contract LPProvider is BaseUpgradable {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public lpLockAmount;
    /* ========== EVENTS ========== */
    event AddLiquidity(uint256 amountA, uint256 amountB, uint256 liquidity);
    event AddLiquidityETH(uint256 amountToken, uint256 amountETH, uint256 liquidity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    fallback() external payable {}

    function initialize() external initializer {
        __Base_init();
    }

    function addLiquidity(
        address lpToken,
        address routerAddress,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) external onlyAdmin {
        require(
            IERC20(tokenA).balanceOf(address(this)) >= amountADesired,
            "LPProvider: Invalid balance - tokenA"
        );
        require(
            IERC20(tokenB).balanceOf(address(this)) >= amountBDesired,
            "LPProvider: Invalid balance - tokenB"
        );

        IERC20(tokenA).safeDecreaseAllowance(routerAddress, 0);
        IERC20(tokenB).safeDecreaseAllowance(routerAddress, 0);

        IERC20(tokenA).safeIncreaseAllowance(routerAddress, amountADesired);
        IERC20(tokenB).safeIncreaseAllowance(routerAddress, amountBDesired);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = IVanillaRouter02(routerAddress)
            .addLiquidity(
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                address(this),
                deadline
            );

        lpLockAmount[lpToken] += liquidity;

        emit AddLiquidity(amountA, amountB, liquidity);
    }

    function addLiquidityETH(
        address lpToken,
        address routerAddress,
        address token,
        uint256 amountETH,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    ) external onlyAdmin {
        require(address(this).balance >= amountETH, "LPProvider: Invalid balance - amountETH");
        require(
            IERC20(token).balanceOf(address(this)) >= amountTokenDesired,
            "LPProvider: Invalid balance - amountTokenDesired"
        );

        IERC20(token).safeDecreaseAllowance(routerAddress, 0);
        IERC20(token).safeIncreaseAllowance(routerAddress, amountTokenDesired);

        (uint256 amountToken, uint256 amountETH_, uint256 liquidity) = IVanillaRouter02(
            routerAddress
        ).addLiquidityETH{value: amountETH}(
            token,
            amountTokenDesired,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );

        lpLockAmount[lpToken] += liquidity;

        emit AddLiquidityETH(amountToken, amountETH_, liquidity);
    }
}
