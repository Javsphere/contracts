const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployToken2Fixture,
    deployUniswapFixture,
} = require("../common/mocks");
const { ADMIN_ERROR } = require("../common/constanst");

describe("CommunityLaunchETH contract", () => {
    let hhCommunityLaunch;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let erc20Token;
    let wdfiToken;
    let uniswapFactory;
    let uniswapRouter;
    let uniswapPairContract;
    let basePair;
    let saleActiveError;
    let startTokenPrice;
    let incPricePerBlock;
    let startBlock;

    before(async () => {
        const communityLaunch = await ethers.getContractFactory("CommunityLaunchETH");

        [owner, addr1, addr2, admin, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        const data = await helpers.loadFixture(deployUniswapFixture);
        [wdfiToken, uniswapFactory, uniswapRouter, uniswapPairContract] = Object.values(data);

        startTokenPrice = ethers.parseEther("0.02");
        incPricePerBlock = ethers.parseEther("0.0000002");

        // create pairs
        await uniswapFactory.createPair(wdfiToken.target, erc20Token.target);
        let allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        basePair = uniswapPairContract.attach(pairCreated);

        hhCommunityLaunch = await upgrades.deployProxy(
            communityLaunch,
            [await erc20Token.getAddress(), basePair.target, ethers.parseEther("100")],

            {
                initializer: "initialize",
            },
        );

        saleActiveError = "CommunityLaunch: contract is not available right now";

        // add liquidity
        const amountWeth = ethers.parseEther("100");
        const amount0 = ethers.parseEther("500");
        await wdfiToken.deposit({ value: amountWeth });
        await erc20Token.mint(owner.address, amount0);

        await wdfiToken.approve(uniswapRouter.target, ethers.parseEther("100000"));
        await erc20Token.approve(uniswapRouter.target, ethers.parseEther("100000"));

        await uniswapRouter.addLiquidity(
            erc20Token.target,
            wdfiToken.target,
            amount0,
            amountWeth,
            1,
            1,
            owner.address,
            // wait time
            "999999999999999999999999999999",
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhCommunityLaunch.owner()).to.equal(owner.address);
        });

        it("Should set the right usdt address", async () => {
            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token.target);
        });

        it("Should set the right pair address", async () => {
            await expect(await hhCommunityLaunch.pairAddress()).to.equal(basePair.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhCommunityLaunch.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right availableTokens", async () => {
            await expect(await hhCommunityLaunch.availableTokens()).to.equal(
                ethers.parseEther("100"),
            );
        });

        it("Should set the right isSaleActive flag", async () => {
            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set the admin address", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setAdminAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhCommunityLaunch.setAdminAddress(admin.address);

            await expect(await hhCommunityLaunch.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when setAvailableTokens", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setAvailableTokens(100),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setAvailableTokens", async () => {
            await hhCommunityLaunch.setAvailableTokens(ethers.parseEther("100"));

            await expect(await hhCommunityLaunch.availableTokens()).to.equal(
                ethers.parseEther("100"),
            );
        });

        it("Should revert when setUSDTAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setUSDTAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setUSDTAddress", async () => {
            await hhCommunityLaunch.setUSDTAddress(erc20Token.target);

            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token.target);
        });

        it("Should revert when setPairAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setPairAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setPairAddress", async () => {
            await hhCommunityLaunch.setPairAddress(basePair.target);

            await expect(await hhCommunityLaunch.pairAddress()).to.equal(basePair.target);
        });

        it("Should revert when set setSaleActive", async () => {
            await expect(hhCommunityLaunch.connect(addr1).setSaleActive(true)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should set the setSaleActive", async () => {
            await hhCommunityLaunch.setSaleActive(true);

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(true);
        });

        it("Should revert when buy with isSaleActive = false", async () => {
            await hhCommunityLaunch.setSaleActive(false);

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, {
                    value: ethers.parseEther("1.0"),
                }),
            ).to.be.revertedWith(saleActiveError);

            await hhCommunityLaunch.setSaleActive(true);
        });

        it("Should buy jav tokens with dusd", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("5");
            await erc20Token.mint(addr1.address, usdtAmount);
            await erc20Token.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr2.address, usdtAmount, {
                    value: 0,
                }),
            )
                .emit(hhCommunityLaunch, "TokensPurchased")
                .withArgs(addr1.address, addr2.address, usdtAmount);

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                usdtAmount,
            );
        });

        it("Should buy jav tokens with dfi", async () => {
            await helpers.mine(10);

            const buyNativeAmount = ethers.parseEther("1.0");
            const amount = ethers.parseEther("5");

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr2.address, 0, {
                    value: buyNativeAmount,
                }),
            )
                .emit(hhCommunityLaunch, "TokensPurchased")
                .withArgs(addr1.address, addr2.address, amount);

            await expect(await ethers.provider.getBalance(hhCommunityLaunch.target)).to.be.equal(
                buyNativeAmount,
            );
        });

        it("Should revert when withdraw ADMIN_ERROR", async () => {
            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .withdraw(erc20Token.target, addr1.address, ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when withdraw Invalid amount", async () => {
            await expect(
                hhCommunityLaunch.withdraw(
                    erc20Token.target,
                    addr1.address,
                    ethers.parseEther("100"),
                ),
            ).to.be.revertedWith("CommunityLaunch: Invalid amount");
        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.05");
            const balanceBefore = await erc20Token.balanceOf(addr1.address);

            await hhCommunityLaunch.withdraw(erc20Token.target, addr1.address, amount);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(
                amount + balanceBefore,
            );
        });

        it("Should revert when withdrawEth ADMIN_ERROR", async () => {
            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .withdrawEth(addr1.address, ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when withdrawEth Invalid amount", async () => {
            await expect(
                hhCommunityLaunch.withdrawEth(addr1.address, ethers.parseEther("100")),
            ).to.be.revertedWith("CommunityLaunch: Invalid amount");
        });

        it("Should withdrawEth", async () => {
            const amount = ethers.parseEther("0.05");
            const balanceBefore = await ethers.provider.getBalance(addr1.address);

            await hhCommunityLaunch.withdrawEth(addr1.address, amount);

            await expect(await ethers.provider.getBalance(addr1.address)).to.equal(
                amount + balanceBefore,
            );
        });
    });
});
