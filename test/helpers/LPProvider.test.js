const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployUniswapFixture,
    deployToken2Fixture,
} = require("../common/mocks");
const { ADMIN_ERROR } = require("../common/constanst");

describe("LPProvider contract", () => {
    let hhLpProvider;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let nonZeroAddress;
    let erc20Token;
    let erc20Token2;
    let wdfiToken;
    let uniswapFactory;
    let uniswapRouter;
    let uniswapPairContract;
    let basePair;
    let pair2;

    before(async () => {
        const lpProvider = await ethers.getContractFactory("LPProvider");
        [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        const data = await helpers.loadFixture(deployUniswapFixture);
        [wdfiToken, uniswapFactory, uniswapRouter, uniswapPairContract] = Object.values(data);

        hhLpProvider = await upgrades.deployProxy(lpProvider, [], {
            initializer: "initialize",
        });

        // create pairs
        await uniswapFactory.createPair(erc20Token.target, wdfiToken.target);
        let allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        basePair = uniswapPairContract.attach(pairCreated);

        await uniswapFactory.createPair(erc20Token.target, erc20Token2.target);
        allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated2 = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        pair2 = uniswapPairContract.attach(pairCreated2);

        // // add liquidity
        // const amountWeth = ethers.parseEther("500");
        // const amount0 = ethers.parseEther("500");
        // await wdfiToken.deposit({ value: amountWeth });
        // await erc20Token.mint(owner.address, amount0);
        // await erc20Token.mint(owner.address, amount0);
        // await erc20Token2.mint(owner.address, amount0);
        //
        // await wdfiToken.approve(uniswapRouter.target, ethers.parseEther("100000"));
        // await erc20Token.approve(uniswapRouter.target, ethers.parseEther("100000"));
        // await erc20Token2.approve(uniswapRouter.target, ethers.parseEther("100000"));
        //
        // await uniswapRouter.addLiquidity(
        //     erc20Token.target,
        //     wdfiToken.target,
        //     amount0,
        //     amountWeth,
        //     1,
        //     1,
        //     owner.address,
        //     // wait time
        //     "999999999999999999999999999999",
        // );
        //
        // await uniswapRouter.addLiquidity(
        //     erc20Token.target,
        //     erc20Token2.target,
        //     amount0,
        //     amount0,
        //     1,
        //     1,
        //     owner.address,
        //     // wait time
        //     "999999999999999999999999999999",
        // );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhLpProvider.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhLpProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhLpProvider.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhLpProvider.connect(addr1).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhLpProvider.pause();

            await expect(await hhLpProvider.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhLpProvider.connect(addr1).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhLpProvider.unpause();

            await expect(await hhLpProvider.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhLpProvider.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhLpProvider.setAdminAddress(owner.address);

            await expect(await hhLpProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when addLiquidity - admin error", async () => {
            await expect(
                hhLpProvider
                    .connect(addr1)
                    .addLiquidity(
                        pair2.target,
                        owner.address,
                        owner.address,
                        owner.address,
                        0,
                        0,
                        0,
                        0,
                        0,
                    ),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when addLiquidity - Invalid balance - tokenA", async () => {
            await expect(
                hhLpProvider.addLiquidity(
                    pair2.target,
                    uniswapRouter.target,
                    erc20Token.target,
                    erc20Token2.target,
                    ethers.parseEther("100"),
                    0,
                    0,
                    0,
                    0,
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - tokenA");
        });

        it("Should revert when addLiquidity - Invalid balance - tokenB", async () => {
            await expect(
                hhLpProvider.addLiquidity(
                    pair2.target,
                    uniswapRouter.target,
                    erc20Token.target,
                    erc20Token2.target,
                    0,
                    ethers.parseEther("100"),
                    0,
                    0,
                    0,
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - tokenB");
        });

        it("Should addLiquidity", async () => {
            const tokenAAmount = ethers.parseEther("50");
            const tokenBAmount = ethers.parseEther("100");

            await erc20Token.mint(hhLpProvider.target, tokenAAmount);
            await erc20Token2.mint(hhLpProvider.target, tokenBAmount);

            await hhLpProvider.addLiquidity(
                pair2.target,
                uniswapRouter.target,
                erc20Token.target,
                erc20Token2.target,
                tokenAAmount,
                tokenBAmount,
                0,
                0,
                "999999999999999999999999999999",
            );

            const lpBalance = await pair2.balanceOf(hhLpProvider.target);
            await expect(await hhLpProvider.lpLockAmount(pair2.target)).to.be.equal(lpBalance);
        });

        it("Should revert when addLiquidityETH - admin error", async () => {
            await expect(
                hhLpProvider
                    .connect(addr1)
                    .addLiquidityETH(pair2.target, owner.address, owner.address, 0, 0, 0, 0, 0),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when addLiquidityETH - Invalid balance - amountETH", async () => {
            await expect(
                hhLpProvider.addLiquidityETH(
                    pair2.target,
                    uniswapRouter.target,
                    erc20Token.target,
                    ethers.parseEther("100"),
                    0,
                    0,
                    0,
                    0,
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - amountETH");
        });

        it("Should revert when addLiquidityETH - Invalid balance - amountTokenDesired", async () => {
            await expect(
                hhLpProvider.addLiquidityETH(
                    pair2.target,
                    uniswapRouter.target,
                    erc20Token.target,
                    0,
                    ethers.parseEther("100"),
                    0,
                    0,
                    0,
                ),
            ).to.be.revertedWith("LPProvider: Invalid balance - amountTokenDesired");
        });

        it("Should addLiquidityETH", async () => {
            const ETHAmount = ethers.parseEther("50");
            const tokenBAmount = ethers.parseEther("100");

            await addr1.sendTransaction({
                to: hhLpProvider.target,
                value: ETHAmount,
            });
            await erc20Token.mint(hhLpProvider.target, tokenBAmount);

            await hhLpProvider.addLiquidityETH(
                basePair.target,
                uniswapRouter.target,
                erc20Token.target,
                ETHAmount,
                tokenBAmount,
                0,
                0,
                "999999999999999999999999999999",
            );

            const lpBalance = await basePair.balanceOf(hhLpProvider.target);
            await expect(await hhLpProvider.lpLockAmount(basePair.target)).to.be.equal(lpBalance);
        });
    });
});
