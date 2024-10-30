const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployUniswapV3Fixture,
    deployToken2Fixture,
} = require("../common/mocks");
const { ADMIN_ERROR, MANAGER_ERROR } = require("../common/constanst");
const { encodeSqrtRatioX96 } = require("@uniswap/v3-sdk");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("RewardsDistributor contract", () => {
    let hhRewardsDistributor;
    let owner;
    let bot;
    let addr2;
    let addr3;
    let nonZeroAddress;
    let javToken;
    let freezer;
    let staking;
    let erc20Token2;
    let wdfiTokenV3;
    let uniswapV3Factory;
    let uniswapV3Router;
    let uniswapV3Pool;
    let nonfungiblePositionManager;

    before(async () => {
        const RewardsDistributor = await ethers.getContractFactory("RewardsDistributor");
        [owner, bot, addr2, addr3, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        javToken = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);

        const freezerContractFactory = await ethers.getContractFactory("JavFreezerMock");
        freezer = await freezerContractFactory.deploy();
        await freezer.waitForDeployment();
        staking = await freezerContractFactory.deploy();
        await staking.waitForDeployment();

        const dataV3 = await helpers.loadFixture(deployUniswapV3Fixture);
        [
            wdfiTokenV3,
            uniswapV3Factory,
            uniswapV3Router,
            uniswapV3Pool,
            nonfungiblePositionManager,
        ] = Object.values(dataV3);

        hhRewardsDistributor = await upgrades.deployProxy(
            RewardsDistributor,
            [
                javToken.target, // _javAddress,
                uniswapV3Router.target, // _swapRouter,
                staking.target, // _stakingAddress,
                freezer.target, // _freezerAddress,
                50, // _burnPercent,
                70, // _freezerPercent,
                [owner.address], // _allowedAddresses_
            ],
            {
                initializer: "initialize",
            },
        );

        // create pairs
        const fee = 3000;
        const amount0ToMint = ethers.parseEther("5000");
        const amount1ToMint = ethers.parseEther("5000");
        await javToken.mint(owner.address, amount0ToMint);
        await wdfiTokenV3.deposit({ value: amount1ToMint });
        await wdfiTokenV3.approve(nonfungiblePositionManager.target, amount0ToMint);
        await javToken.approve(nonfungiblePositionManager.target, amount1ToMint);

        await uniswapV3Factory.createPool(javToken.target, wdfiTokenV3.target, fee);
        const poolAddress = await uniswapV3Factory.getPool(
            javToken.target,
            wdfiTokenV3.target,
            fee,
        );
        const pool = uniswapV3Pool.attach(poolAddress);
        const price = encodeSqrtRatioX96(1, 1).toString();

        await pool.initialize(price);
        const tick = (await pool.slot0()).tick;
        const tickSpacing = await pool.tickSpacing();

        const mintParams = {
            token0: javToken.target,
            token1: wdfiTokenV3.target,
            fee: fee,
            tickLower: tick - tickSpacing * BigInt(2),
            tickUpper: tick + tickSpacing * BigInt(2),
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner.address,
            deadline: 10000000000,
        };
        await nonfungiblePositionManager.mint(mintParams);
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhRewardsDistributor.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhRewardsDistributor.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhRewardsDistributor.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhRewardsDistributor.connect(bot).pause()).to.be.revertedWith(
                MANAGER_ERROR,
            );
        });

        it("Should set pause", async () => {
            await hhRewardsDistributor.pause();

            await expect(await hhRewardsDistributor.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhRewardsDistributor.connect(bot).unpause()).to.be.revertedWith(
                MANAGER_ERROR,
            );
        });

        it("Should set unpause", async () => {
            await hhRewardsDistributor.unpause();

            await expect(await hhRewardsDistributor.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhRewardsDistributor.connect(bot).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhRewardsDistributor.setAdminAddress(owner.address);

            await expect(await hhRewardsDistributor.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when addAllowedAddress", async () => {
            await expect(
                hhRewardsDistributor.connect(bot).addAllowedAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addAllowedAddress", async () => {
            await hhRewardsDistributor.addAllowedAddress(
                "0x0000000000000000000000000000000000000000",
            );
        });

        it("Should revert when removeAllowedAddress", async () => {
            await expect(
                hhRewardsDistributor.connect(bot).removeAllowedAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should removeAllowedAddress", async () => {
            await hhRewardsDistributor.removeAllowedAddress(
                "0x0000000000000000000000000000000000000000",
            );
        });

        it("Should revert when setPercents", async () => {
            await expect(hhRewardsDistributor.connect(bot).setPercents(1, 1)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should setPercents", async () => {
            const burnPercent = 50;
            const freezerPercent = 70;
            await hhRewardsDistributor.setPercents(burnPercent, freezerPercent);

            await expect(await hhRewardsDistributor.burnPercent()).to.equal(burnPercent);
            await expect(await hhRewardsDistributor.freezerPercent()).to.equal(freezerPercent);
        });

        it("Should revert when setTokenPoolFee", async () => {
            await expect(
                hhRewardsDistributor.connect(bot).setPercents(wdfiTokenV3.target, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setTokenPoolFee", async () => {
            const fee = 3000;
            await hhRewardsDistributor.setTokenPoolFee(wdfiTokenV3.target, fee);

            await expect(await hhRewardsDistributor.tokenPoolFee(wdfiTokenV3.target)).to.equal(fee);
        });

        it("Should revert when distributeRewards", async () => {
            await expect(
                hhRewardsDistributor.connect(bot).distributeRewards([wdfiTokenV3.target]),
            ).to.be.revertedWith("RewardsDistributor: only allowed addresses");
        });

        // it("Should distributeRewards", async () => {
        //     const javAmount = ethers.parseEther("40");
        //     const wdfiAmount = ethers.parseEther("30");
        //
        //     await javToken.mint(owner.address, javAmount);
        //     await wdfiTokenV3.deposit({ value: wdfiAmount });
        //
        //     await javToken.transfer(hhRewardsDistributor.target, javAmount);
        //     await wdfiTokenV3.transfer(hhRewardsDistributor.target, wdfiAmount);
        //
        //     await hhRewardsDistributor.distributeRewards([wdfiTokenV3.target, javToken.target]);
        //
        //     await expect(await javToken.balanceOf(hhRewardsDistributor.target)).to.equal(0);
        //     await expect(await wdfiTokenV3.balanceOf(hhRewardsDistributor.target)).to.equal(0);
        // });
    });
});
