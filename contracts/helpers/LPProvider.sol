// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IRewardsDistributor.sol";
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
    address public wdfiAddress;
    address public rewardsDistributorAddress;

    /* ========== EVENTS ========== */
    event SetBotAddress(address indexed _address);
    event SetRewardsDistributorAddress(address indexed _address);
    event AddLiquidity(uint256 amountA, uint256 amountB, uint256 liquidity);
    event AddLiquidityETH(uint256 amountToken, uint256 amountETH, uint256 liquidity);
    event SetWDFIAddress(address indexed _address);
    event SwapToWDFI(uint256 indexed amount);

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

    function setRewardsDistributorAddress(address _address) external onlyAdmin {
        rewardsDistributorAddress = _address;

        emit SetRewardsDistributorAddress(_address);
    }

    function setWDFIAddress(address _address) external onlyAdmin {
        wdfiAddress = _address;
        emit SetWDFIAddress(_address);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function swapToWDFI(uint256 _amount) external onlyAdmin {
        require(address(this).balance >= _amount, "LPProvider: Invalid balance - dfi");

        payable(wdfiAddress).transfer(_amount);

        emit SwapToWDFI(_amount);
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
        (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(
            _tokenId
        );
        _collectFees(_tokenId);

        address[] memory _tokens = new address[](2);
        _tokens[0] = token0;
        _tokens[1] = token1;
        IRewardsDistributor(rewardsDistributorAddress).distributeRewards(_tokens);
    }

    function _collectFees(uint256 tokenId) private {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
            .CollectParams({
                tokenId: tokenId,
                recipient: rewardsDistributorAddress,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        nonfungiblePositionManager.collect(params);
    }
}
