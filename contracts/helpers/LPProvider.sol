// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IVanillaRouter02.sol";
import "../interfaces/IERC20Extended.sol";
import "../base/BaseUpgradable.sol";

contract LPProvider is IERC721Receiver, BaseUpgradable {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public nonfungiblePositionManager;
    ISwapRouter public swapRouter;
    IVanillaRouter02 public routerV2;

    address public botAddress;
    uint256 public burnPercent;
    address public stakingAddress;

    mapping(address => uint256) public lpLockAmountV2;
    mapping(uint256 => uint256) public lpLockAmountV3;
    uint256[] public pairsTokenId;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event SetStakingAddress(address indexed _address);
    event AddLiquidity(uint256 amountA, uint256 amountB, uint256 liquidity);
    event AddLiquidityETH(uint256 amountToken, uint256 amountETH, uint256 liquidity);
    event MintNewPosition(uint256 indexed tokenId);

    modifier onlyBot() {
        require(msg.sender == botAddress, "LPProvider: only bot");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    fallback() external payable {}

    function initialize(
        address _nonfungiblePositionManager,
        address _routerAddressV2,
        address _swapRouter,
        address _botAddress
    ) external initializer {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        swapRouter = ISwapRouter(_swapRouter);
        routerV2 = IVanillaRouter02(_routerAddressV2);

        botAddress = _botAddress;

        __Base_init();
    }

    function setBotAddress(address _address) external onlyAdmin {
        botAddress = _address;

        emit SetBotAddress(_address);
    }

    function setStakingAddress(address _address) external onlyAdmin {
        stakingAddress = _address;

        emit SetStakingAddress(_address);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function mintNewPosition(
        address token0,
        address token1,
        uint24 _poolFee,
        uint256 amount0ToMint,
        uint256 amount1ToMint,
        int24 tickLower,
        int24 tickUpper
    ) external onlyAdmin {
        require(
            IERC20(token0).balanceOf(address(this)) >= amount0ToMint,
            "LPProvider: Invalid balance - token0"
        );
        require(
            IERC20(token1).balanceOf(address(this)) >= amount1ToMint,
            "LPProvider: Invalid balance - token1"
        );

        // Approve the position manager
        IERC20(token0).safeIncreaseAllowance(address(nonfungiblePositionManager), amount0ToMint);
        IERC20(token1).safeIncreaseAllowance(address(nonfungiblePositionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
            .MintParams({
                token0: token0,
                token1: token1,
                fee: _poolFee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (uint256 tokenId, uint128 liquidity, , ) = nonfungiblePositionManager.mint(params);

        pairsTokenId.push(tokenId);

        lpLockAmountV3[tokenId] += liquidity;

        IERC20(token0).safeDecreaseAllowance(address(nonfungiblePositionManager), 0);
        IERC20(token1).safeDecreaseAllowance(address(nonfungiblePositionManager), 0);

        emit MintNewPosition(tokenId);
    }

    function addLiquidityV3(
        uint256 tokenId,
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external onlyAdmin {
        require(
            IERC20(token0).balanceOf(address(this)) >= amount0Desired,
            "LPProvider: Invalid balance - token0"
        );
        require(
            IERC20(token1).balanceOf(address(this)) >= amount1Desired,
            "LPProvider: Invalid balance - token1"
        );

        IERC20(token0).safeDecreaseAllowance(address(nonfungiblePositionManager), 0);
        IERC20(token1).safeDecreaseAllowance(address(nonfungiblePositionManager), 0);

        IERC20(token0).safeIncreaseAllowance(address(nonfungiblePositionManager), amount0Desired);
        IERC20(token1).safeIncreaseAllowance(address(nonfungiblePositionManager), amount1Desired);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1000
            });

        (uint128 liquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager
            .increaseLiquidity(params);

        lpLockAmountV3[tokenId] += liquidity;

        emit AddLiquidity(amount0, amount1, liquidity);
    }

    function addLiquidityV2(
        address lpToken,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external onlyAdmin {
        require(
            IERC20(tokenA).balanceOf(address(this)) >= amountADesired,
            "LPProvider: Invalid balance - tokenA"
        );
        require(
            IERC20(tokenB).balanceOf(address(this)) >= amountBDesired,
            "LPProvider: Invalid balance - tokenB"
        );

        IERC20(tokenA).safeDecreaseAllowance(address(routerV2), 0);
        IERC20(tokenB).safeDecreaseAllowance(address(routerV2), 0);

        IERC20(tokenA).safeIncreaseAllowance(address(routerV2), amountADesired);
        IERC20(tokenB).safeIncreaseAllowance(address(routerV2), amountBDesired);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = routerV2.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );

        lpLockAmountV2[lpToken] += liquidity;

        emit AddLiquidity(amountA, amountB, liquidity);
    }

    function addLiquidityETHV2(
        address lpToken,
        address token,
        uint256 amountETH,
        uint256 amountTokenDesired
    ) external onlyAdmin {
        require(address(this).balance >= amountETH, "LPProvider: Invalid balance - amountETH");
        require(
            IERC20(token).balanceOf(address(this)) >= amountTokenDesired,
            "LPProvider: Invalid balance - amountTokenDesired"
        );

        IERC20(token).safeDecreaseAllowance(address(routerV2), 0);
        IERC20(token).safeIncreaseAllowance(address(routerV2), amountTokenDesired);

        (uint256 amountToken, uint256 amountETH_, uint256 liquidity) = routerV2.addLiquidityETH{
            value: amountETH
        }(token, amountTokenDesired, 0, 0, address(this), block.timestamp + 1000);

        lpLockAmountV2[lpToken] += liquidity;

        emit AddLiquidityETH(amountToken, amountETH_, liquidity);
    }

    function claimAndDistributeRewards(uint256 _tokenId) external onlyBot {
        //        (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager
        //            .positions(_tokenId);

        _collectFees(_tokenId);
    }

    function _collectFees(uint256 tokenId) private {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
            .CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        nonfungiblePositionManager.collect(params);
    }
}
