const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployUniswapV3Fixture,
    deployToken2Fixture,
} = require("../common/mocks");
const { ADMIN_ERROR } = require("../common/constanst");
const { encodeSqrtRatioX96 } = require("@uniswap/v3-sdk");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("JavLiquidityProvider contract", () => {
    let hhJavLiquidityProvider;
    let owner;
    let bot;
    let addr2;
    let addr3;
    let javPriceAggregator;
    let nonZeroAddress;
    let erc20Token;
    let erc20Token2;
    let wdfiTokenV3;
    let uniswapV3Factory;
    let uniswapV3Router;
    let uniswapV3Pool;
    let nonfungiblePositionManager;
    const token1PriceId = "0x12635656e5b860830354ee353bce5f76d17342f9dbb560e3180d878b5d53bae3";
    const token2PriceId = "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6";
    const token3PriceId = "0xb3b9faf5d52f4cc87ec09fd94cb22c9dc62a8c1759b2a045faae791f8771a723";

    async function deployJavPriceAggregator() {
        const javPriceAggregatorFactory = await ethers.getContractFactory(
            "contracts/helpers/JavPriceAggregator.sol:JavPriceAggregator",
        );
        [owner, ...addrs] = await ethers.getSigners();
        const javPriceAggregator = await upgrades.deployProxy(
            javPriceAggregatorFactory,
            [[owner.address]],
            {
                initializer: "initialize",
            },
        );
        await javPriceAggregator.waitForDeployment();
        return javPriceAggregator;
    }

    before(async () => {
        const JavLiquidityProvider = await ethers.getContractFactory("JavLiquidityProvider");
        [owner, bot, addr2, addr3, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        javPriceAggregator = await helpers.loadFixture(deployJavPriceAggregator);

        const dataV3 = await helpers.loadFixture(deployUniswapV3Fixture);
        [
            wdfiTokenV3,
            uniswapV3Factory,
            uniswapV3Router,
            uniswapV3Pool,
            nonfungiblePositionManager,
        ] = Object.values(dataV3);

        hhJavLiquidityProvider = await upgrades.deployProxy(
            JavLiquidityProvider,
            [
                javPriceAggregator.target, //  _priceAggregator,
                uniswapV3Router.target, // _swapRouter,
                "0x0000000000000000000000000000000000000000", //  _jlpToken,
                "0x0000000000000000000000000000000000000000", //  _pnlHandler,
                0, // _buyFee,
                0, // _sellFee,
                [
                    {
                        asset: erc20Token.target,
                        priceFeed: token1PriceId,
                        targetWeightage: 50,
                        isActive: true,
                    },
                    {
                        asset: erc20Token2.target,
                        priceFeed: token2PriceId,
                        targetWeightage: 20,
                        isActive: true,
                    },
                    {
                        asset: wdfiTokenV3.target,
                        priceFeed: token3PriceId,
                        targetWeightage: 30,
                        isActive: true,
                    },
                ], // _tokens
            ],
            {
                initializer: "initialize",
            },
        );

        // create pairs
        const fee = 3000;

        let amount0ToMint;
        let amount1ToMint;
        let poolAddress;
        let pool;
        let price;
        let tick;
        let tickLower;
        let tickUpper;
        let tickSpacing;
        let mintParams;

        // pool 1
        amount0ToMint = ethers.parseEther("1000");
        amount1ToMint = ethers.parseEther("200");

        await erc20Token.mint(owner.address, amount0ToMint);
        await wdfiTokenV3.deposit({ value: amount1ToMint });

        await erc20Token.approve(nonfungiblePositionManager.target, amount0ToMint);
        await wdfiTokenV3.approve(nonfungiblePositionManager.target, amount1ToMint);

        await uniswapV3Factory.createPool(erc20Token.target, wdfiTokenV3.target, fee);
        poolAddress = await uniswapV3Factory.getPool(erc20Token.target, wdfiTokenV3.target, fee);
        pool = uniswapV3Pool.attach(poolAddress);
        price = encodeSqrtRatioX96(1, 5).toString();

        await pool.initialize(price);
        tick = Number((await pool.slot0()).tick);
        tickSpacing = Number(await pool.tickSpacing());

        tickLower = Math.floor(tick / tickSpacing) * tickSpacing;
        tickUpper = Math.ceil(tick / tickSpacing) * tickSpacing;

        mintParams = {
            token0: erc20Token.target,
            token1: wdfiTokenV3.target,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner.address,
            deadline: 10000000000,
        };
        await nonfungiblePositionManager.mint(mintParams);

        // pool 2
        amount0ToMint = ethers.parseEther("1000");
        amount1ToMint = ethers.parseEther("500");

        await erc20Token.mint(owner.address, amount0ToMint);
        await erc20Token2.mint(owner.address, amount1ToMint);

        await erc20Token.approve(nonfungiblePositionManager.target, amount0ToMint);
        await erc20Token2.approve(nonfungiblePositionManager.target, amount1ToMint);

        await uniswapV3Factory.createPool(erc20Token.target, erc20Token2.target, fee);
        poolAddress = await uniswapV3Factory.getPool(erc20Token.target, erc20Token2.target, fee);
        pool = uniswapV3Pool.attach(poolAddress);
        price = encodeSqrtRatioX96(1, 2).toString();

        await pool.initialize(price);
        tick = Number((await pool.slot0()).tick);
        tickSpacing = Number(await pool.tickSpacing());

        tickLower = Math.floor(tick / tickSpacing) * tickSpacing;
        tickUpper = Math.ceil(tick / tickSpacing) * tickSpacing;

        mintParams = {
            token0: erc20Token.target,
            token1: erc20Token2.target,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner.address,
            deadline: 10000000000,
        };
        await nonfungiblePositionManager.mint(mintParams);

        // pool 3
        amount0ToMint = ethers.parseEther("1000");
        amount1ToMint = ethers.parseEther("400");

        await erc20Token2.mint(owner.address, amount0ToMint);
        await wdfiTokenV3.deposit({ value: amount1ToMint });

        await erc20Token2.approve(nonfungiblePositionManager.target, amount0ToMint);
        await wdfiTokenV3.approve(nonfungiblePositionManager.target, amount1ToMint);

        await uniswapV3Factory.createPool(erc20Token2.target, wdfiTokenV3.target, fee);
        poolAddress = await uniswapV3Factory.getPool(wdfiTokenV3.target, erc20Token2.target, fee);
        pool = uniswapV3Pool.attach(poolAddress);
        price = encodeSqrtRatioX96(4, 10).toString();

        await pool.initialize(price);
        tick = Number((await pool.slot0()).tick);
        tickSpacing = Number(await pool.tickSpacing());

        tickLower = Math.floor(tick / tickSpacing) * tickSpacing;
        tickUpper = Math.ceil(tick / tickSpacing) * tickSpacing;

        mintParams = {
            token0: wdfiTokenV3.target,
            token1: erc20Token2.target,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount1ToMint,
            amount1Desired: amount0ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner.address,
            deadline: 10000000000,
        };
        await nonfungiblePositionManager.mint(mintParams);
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavLiquidityProvider.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavLiquidityProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavLiquidityProvider.paused()).to.equal(false);
        });

        it("Should set prices for JavPriceAggregator", async () => {
            const prices = [
                {
                    id: token1PriceId,
                    price: 10,
                    conf: 0,
                    expo: -1,
                    publishTime: 10000000000,
                },
                {
                    id: token2PriceId,
                    price: 20,
                    conf: 0,
                    expo: -1,
                    publishTime: 10000000000,
                },
                {
                    id: token3PriceId,
                    price: 50,
                    conf: 0,
                    expo: -1,
                    publishTime: 10000000000,
                },
            ];

            await javPriceAggregator.updatePriceFeeds(prices);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavLiquidityProvider.connect(bot).pause()).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should set pause", async () => {
            await hhJavLiquidityProvider.pause();

            await expect(await hhJavLiquidityProvider.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavLiquidityProvider.connect(bot).unpause()).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should set unpause", async () => {
            await hhJavLiquidityProvider.unpause();

            await expect(await hhJavLiquidityProvider.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavLiquidityProvider.connect(bot).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavLiquidityProvider.setAdminAddress(owner.address);

            await expect(await hhJavLiquidityProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should get tvl = 0", async () => {
            await expect(await hhJavLiquidityProvider.tvl()).to.equal(0);
        });

        it("Should get tvl with tokens", async () => {
            const amount1 = ethers.parseEther("50"); //50 usd
            const amount2 = ethers.parseEther("50"); //100 usd
            const amount3 = ethers.parseEther("50"); //250 usd

            await erc20Token.mint(hhJavLiquidityProvider.target, amount1);
            await erc20Token2.mint(hhJavLiquidityProvider.target, amount2);
            await wdfiTokenV3.deposit({ value: amount3 });
            await wdfiTokenV3.transfer(hhJavLiquidityProvider.target, amount3);

            await expect(await hhJavLiquidityProvider.tvl()).to.equal(ethers.parseEther("400"));
        });

        it("Should rebalance", async () => {
            const tvlBefore = await hhJavLiquidityProvider.tvl();
            const token1TvlBefore = await hhJavLiquidityProvider.tokenTvl(0);
            const token2TvlBefore = await hhJavLiquidityProvider.tokenTvl(1);
            const token3TvlBefore = await hhJavLiquidityProvider.tokenTvl(2);

            console.log("token1TvlBefore", token1TvlBefore);
            console.log("token2TvlBefore", token2TvlBefore);
            console.log("token2TvlBefore", token3TvlBefore);
            console.log("tvlBefore", tvlBefore);

            await hhJavLiquidityProvider.rebalanceTokens();

            const tvl = await hhJavLiquidityProvider.tvl();
            const token1Tvl = await hhJavLiquidityProvider.tokenTvl(0);
            const token2Tvl = await hhJavLiquidityProvider.tokenTvl(1);
            const token3Tvl = await hhJavLiquidityProvider.tokenTvl(2);

            console.log("token1Tvl", token1Tvl);
            console.log("token2Tvl", token2Tvl);
            console.log("token3Tvl", token3Tvl);
            console.log("tvl", tvl);

            // await expect(await hhJavLiquidityProvider.tvl()).to.equal(ethers.parseEther("400"));
        });
    });
});
