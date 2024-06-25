const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployUniswapV2Fixture,
    deployUniswapV3Fixture,
    deployToken2Fixture,
} = require("../common/mocks");
const { ADMIN_ERROR } = require("../common/constanst");
const { encodeSqrtRatioX96 } = require("@uniswap/v3-sdk");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("LPProvider contract", () => {
    let hhLPProvider;
    let owner;
    let bot;
    let addr2;
    let addr3;
    let nonZeroAddress;
    let rewardsDistributor;
    let javToken;
    let erc20Token2;
    let wdfiToken;
    let uniswapFactory;
    let uniswapRouter;
    let uniswapPairContract;
    let basePair;
    let pair2;
    let wdfiTokenV3;
    let uniswapV3Factory;
    let uniswapV3Router;
    let uniswapV3Pool;
    let nonfungiblePositionManager;

    before(async () => {
        const LPProvider = await ethers.getContractFactory("LPProvider");
        [owner, bot, addr2, addr3, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        javToken = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        const dataV2 = await helpers.loadFixture(deployUniswapV2Fixture);
        [wdfiToken, uniswapFactory, uniswapRouter, uniswapPairContract] = Object.values(dataV2);

        const dataV3 = await helpers.loadFixture(deployUniswapV3Fixture);
        [
            wdfiTokenV3,
            uniswapV3Factory,
            uniswapV3Router,
            uniswapV3Pool,
            nonfungiblePositionManager,
        ] = Object.values(dataV3);

        const rewardsDistributorFactory = await ethers.getContractFactory("RewardsDistributorMock");
        rewardsDistributor = await rewardsDistributorFactory.deploy();
        await rewardsDistributor.waitForDeployment();

        hhLPProvider = await upgrades.deployProxy(
            LPProvider,
            [
                nonfungiblePositionManager.target, //_nonfungiblePositionManager
                uniswapRouter.target, //_routerAddressV2
                uniswapV3Router.target, //_swapRouter
                bot.address, //_botAddress
            ],
            {
                initializer: "initialize",
            },
        );

        // create pairs v2
        await uniswapFactory.createPair(javToken.target, wdfiToken.target);
        let allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        basePair = uniswapPairContract.attach(pairCreated);

        await uniswapFactory.createPair(javToken.target, erc20Token2.target);
        allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated2 = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        pair2 = uniswapPairContract.attach(pairCreated2);

        // create pairs v3
        const fee = 3000;
        const amount0ToMint = ethers.parseEther("5000");
        const amount1ToMint = ethers.parseEther("5000");
        await javToken.mint(owner.address, amount0ToMint * BigInt(2));
        await erc20Token2.mint(owner.address, amount1ToMint);
        await wdfiTokenV3.deposit({ value: amount1ToMint });
        await wdfiTokenV3.approve(nonfungiblePositionManager.target, amount1ToMint);
        await javToken.approve(nonfungiblePositionManager.target, amount0ToMint * BigInt(2));
        await erc20Token2.approve(nonfungiblePositionManager.target, amount1ToMint);

        await uniswapV3Factory.createPool(javToken.target, wdfiTokenV3.target, fee);
        await uniswapV3Factory.createPool(javToken.target, erc20Token2.target, fee);
        const poolAddress1 = await uniswapV3Factory.getPool(
            javToken.target,
            wdfiTokenV3.target,
            fee,
        );
        const poolAddress2 = await uniswapV3Factory.getPool(
            javToken.target,
            erc20Token2.target,
            fee,
        );
        const pool1 = uniswapV3Pool.attach(poolAddress1);
        const pool2 = uniswapV3Pool.attach(poolAddress2);
        const price = encodeSqrtRatioX96(1, 1).toString();

        await pool1.initialize(price);
        await pool2.initialize(price);
        const tick1 = (await pool1.slot0()).tick;
        const tick2 = (await pool2.slot0()).tick;
        const tickSpacing1 = await pool1.tickSpacing();
        const tickSpacing2 = await pool2.tickSpacing();

        const mintParams1 = {
            token0: javToken.target,
            token1: wdfiTokenV3.target,
            fee: fee,
            tickLower: tick1 - tickSpacing1 * BigInt(2),
            tickUpper: tick1 + tickSpacing1 * BigInt(2),
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner.address,
            deadline: 100000000000,
        };
        const mintParams2 = {
            token0: javToken.target,
            token1: erc20Token2.target,
            fee: fee,
            tickLower: tick2 - tickSpacing2 * BigInt(2),
            tickUpper: tick2 + tickSpacing2 * BigInt(2),
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner.address,
            deadline: 100000000000,
        };
        await nonfungiblePositionManager.mint(mintParams1);
        await nonfungiblePositionManager.mint(mintParams2);
        await nonfungiblePositionManager.transferFrom(owner.address, hhLPProvider.target, 1);
        await nonfungiblePositionManager.transferFrom(owner.address, hhLPProvider.target, 2);
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhLPProvider.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhLPProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhLPProvider.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhLPProvider.connect(bot).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhLPProvider.pause();

            await expect(await hhLPProvider.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhLPProvider.connect(bot).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhLPProvider.unpause();

            await expect(await hhLPProvider.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhLPProvider.connect(bot).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhLPProvider.setAdminAddress(owner.address);

            await expect(await hhLPProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when setRewardsDistributorAddress", async () => {
            await expect(
                hhLPProvider.connect(bot).setRewardsDistributorAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardsDistributorAddress", async () => {
            await hhLPProvider.setRewardsDistributorAddress(rewardsDistributor.target);

            await expect(await hhLPProvider.rewardsDistributorAddress()).to.equal(
                rewardsDistributor.target,
            );
        });

        it("Should revert when addLiquidityV2 - admin error", async () => {
            await expect(
                hhLPProvider
                    .connect(bot)
                    .addLiquidityV2(pair2.target, owner.address, owner.address, 0, 0),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when addLiquidityV2 - Invalid balance - tokenA", async () => {
            await expect(
                hhLPProvider.addLiquidityV2(
                    pair2.target,
                    javToken.target,
                    erc20Token2.target,
                    ethers.parseEther("100"),
                    0,
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - tokenA");
        });

        it("Should revert when addLiquidityV2 - Invalid balance - tokenB", async () => {
            await expect(
                hhLPProvider.addLiquidityV2(
                    pair2.target,
                    javToken.target,
                    erc20Token2.target,
                    0,
                    ethers.parseEther("100"),
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - tokenB");
        });

        it("Should addLiquidityV2", async () => {
            const tokenAAmount = ethers.parseEther("50");
            const tokenBAmount = ethers.parseEther("100");

            await javToken.mint(hhLPProvider.target, tokenAAmount);
            await erc20Token2.mint(hhLPProvider.target, tokenBAmount);

            await hhLPProvider.addLiquidityV2(
                pair2.target,
                javToken.target,
                erc20Token2.target,
                tokenAAmount,
                tokenBAmount,
            );

            const lpBalance = await pair2.balanceOf(hhLPProvider.target);
            await expect(await hhLPProvider.lpLockAmountV2(pair2.target)).to.be.equal(lpBalance);
        });

        it("Should revert when addLiquidityETH - admin error", async () => {
            await expect(
                hhLPProvider.connect(bot).addLiquidityETHV2(pair2.target, owner.address, 0, 0),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when addLiquidityETHV2 - Invalid balance - amountETH", async () => {
            await expect(
                hhLPProvider.addLiquidityETHV2(
                    pair2.target,
                    javToken.target,
                    ethers.parseEther("100"),
                    0,
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - amountETH");
        });

        it("Should revert when addLiquidityETHV2 - Invalid balance - amountTokenDesired", async () => {
            await expect(
                hhLPProvider.addLiquidityETHV2(
                    pair2.target,
                    javToken.target,
                    0,
                    ethers.parseEther("100"),
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - amountTokenDesired");
        });

        it("Should addLiquidityETHV2", async () => {
            const ETHAmount = ethers.parseEther("50");
            const tokenBAmount = ethers.parseEther("100");

            await bot.sendTransaction({
                to: hhLPProvider.target,
                value: ETHAmount,
            });
            await javToken.mint(hhLPProvider.target, tokenBAmount);

            await hhLPProvider.addLiquidityETHV2(
                basePair.target,
                javToken.target,
                ETHAmount,
                tokenBAmount,
            );

            const lpBalance = await basePair.balanceOf(hhLPProvider.target);
            await expect(await hhLPProvider.lpLockAmountV2(basePair.target)).to.be.equal(lpBalance);
        });

        it("Should add addLiquidityV3", async () => {
            const fee = 3000;
            const amount0 = ethers.parseEther("100");
            const amount1 = ethers.parseEther("100");
            const tokenId = 1;

            await javToken.mint(hhLPProvider.target, amount0);
            await wdfiTokenV3.deposit({ value: amount1 });
            await wdfiTokenV3.transfer(hhLPProvider.target, amount1);

            await hhLPProvider.addLiquidityV3(
                tokenId,
                javToken.target,
                wdfiTokenV3.target,
                amount0,
                amount1,
            );

            const position = await nonfungiblePositionManager.positions(tokenId);

            await expect(position[2]).to.be.equal(javToken.target);
            await expect(position[3]).to.be.equal(wdfiTokenV3.target);
            await expect(position[4]).to.be.equal(fee);
        });

        it("Should swap", async () => {
            const fee = 3000;
            const amount = ethers.parseEther("1");

            await javToken.mint(owner.address, amount);
            await javToken.approve(uniswapV3Router.target, amount);

            const javParams = {
                tokenIn: javToken.target,
                tokenOut: wdfiTokenV3.target,
                fee: fee,
                recipient: addr2.address,
                deadline: 111111111111111,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            };
            await uniswapV3Router.exactInputSingle(javParams);

            await wdfiTokenV3.deposit({ value: amount });
            await wdfiTokenV3.approve(uniswapV3Router.target, amount);

            const wdfiParams = {
                tokenIn: wdfiTokenV3.target,
                tokenOut: javToken.target,
                fee: fee,
                recipient: addr2.address,
                deadline: 111111111111111,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            };
            await uniswapV3Router.exactInputSingle(wdfiParams);
        });

        it("Should claimAndDistributeRewards", async () => {
            const tokenIds = [1, 2];

            const wdfiBalanceBefore = await wdfiTokenV3.balanceOf(hhLPProvider.target);

            await hhLPProvider.connect(bot).claimAndDistributeRewards(tokenIds);

            await expect(await javToken.balanceOf(hhLPProvider.target)).to.equal(0);
            await expect(await wdfiTokenV3.balanceOf(hhLPProvider.target)).to.equal(
                wdfiBalanceBefore,
            );

            await expect(await javToken.balanceOf(rewardsDistributor.target)).to.not.equal(0);
            await expect(await wdfiTokenV3.balanceOf(rewardsDistributor.target)).to.not.equal(0);
        });
    });
});
