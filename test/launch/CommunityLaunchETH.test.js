const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployTokenFixture } = require("../common/mocks");
const { ADMIN_ERROR } = require("../common/constanst");

describe("CommunityLaunchETH contract", () => {
    let hhCommunityLaunch;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let erc20Token;

    let saleActiveError;

    before(async () => {
        const communityLaunch = await ethers.getContractFactory("CommunityLaunchETH");

        [owner, addr1, addr2, admin, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        hhCommunityLaunch = await upgrades.deployProxy(
            communityLaunch,
            [await erc20Token.getAddress(), ethers.parseEther("100")],

            {
                initializer: "initialize",
            },
        );

        saleActiveError = "CommunityLaunch: contract is not available right now";
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhCommunityLaunch.owner()).to.equal(owner.address);
        });

        it("Should set the right usdt address", async () => {
            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token.target);
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
            await hhCommunityLaunch.setAvailableTokens(ethers.parseEther("70"));

            await expect(await hhCommunityLaunch.availableTokens()).to.equal(
                ethers.parseEther("70"),
            );
        });

        it("Should revert when setTokensPerTrx", async () => {
            await expect(hhCommunityLaunch.connect(addr1).setTokensPerTrx(100)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should setTokensPerTrx", async () => {
            await hhCommunityLaunch.setTokensPerTrx(ethers.parseEther("50"));

            await expect(await hhCommunityLaunch.tokensPerTrx()).to.equal(ethers.parseEther("50"));
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
                hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, false),
            ).to.be.revertedWith(saleActiveError);

            await hhCommunityLaunch.setSaleActive(true);
        });

        it("Should revert when buy tokens - tokensPerTrx", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("60");
            await erc20Token.mint(addr1.address, usdtAmount);
            await erc20Token.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr1.address, usdtAmount, false),
            ).to.be.revertedWith("CommunityLaunch: Invalid tokens amount - max amount");
        });

        it("Should buy tokens", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("50");
            await erc20Token.mint(addr1.address, usdtAmount);
            await erc20Token.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);

            const availableTokensBefore = await hhCommunityLaunch.availableTokens();

            await expect(hhCommunityLaunch.connect(addr1).buy(addr2.address, usdtAmount, true))
                .emit(hhCommunityLaunch, "TokensPurchased")
                .withArgs(addr1.address, addr2.address, usdtAmount, true);

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                usdtAmount,
            );
            await expect(await hhCommunityLaunch.availableTokens()).to.be.equal(
                availableTokensBefore - usdtAmount,
            );
        });

        it("Should revert when buy tokens - availableTokens", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("50");
            await erc20Token.mint(addr1.address, usdtAmount);
            await erc20Token.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr1.address, usdtAmount, false),
            ).to.be.revertedWith("CommunityLaunch: Invalid amount for purchase");
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
    });
});
