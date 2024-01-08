const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { address } = require("hardhat/internal/core/config/config-validation");
const { ADMIN_ERROR } = require("./common/constanst");

describe("DutchAuctionFactory contract", () => {
    let hhDAuctionF;
    let owner;
    let addr1;
    let tokenAddress;
    let admin;
    let multiSignWallet;

    before(async () => {
        const dutchAuctionFactory = await ethers.getContractFactory("DutchAuctionFactory");
        [owner, addr1, admin, multiSignWallet, ...addrs] = await ethers.getSigners();
        tokenAddress = ethers.Wallet.createRandom().address;

        hhDAuctionF = await upgrades.deployProxy(
            dutchAuctionFactory,
            [tokenAddress, multiSignWallet.address],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhDAuctionF.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {
            await expect(await hhDAuctionF.tokenAddress()).to.equal(tokenAddress);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhDAuctionF.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right multi sign wallet address", async () => {
            await expect(await hhDAuctionF.multiSignWallet()).to.equal(multiSignWallet.address);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set the admin address", async () => {
            await expect(
                hhDAuctionF.connect(addr1).setAdminAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhDAuctionF.setAdminAddress(admin.address);

            await expect(await hhDAuctionF.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when set the token address", async () => {
            await expect(
                hhDAuctionF.connect(addr1).setTokenAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the token address", async () => {
            await hhDAuctionF.setTokenAddress(tokenAddress);

            await expect(await hhDAuctionF.tokenAddress()).to.equal(tokenAddress);
        });

        it("Should revert when set the multi sign wallet address", async () => {
            await expect(
                hhDAuctionF.connect(addr1).setMultiSignWalletAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the multi sign wallet address", async () => {
            await hhDAuctionF.setMultiSignWalletAddress(multiSignWallet.address);

            await expect(await hhDAuctionF.multiSignWallet()).to.equal(multiSignWallet.address);
        });

        it("Should revert deploy multisign error", async () => {
            await expect(hhDAuctionF.connect(addr1).deploy(1, 2, 3, 4)).to.be.revertedWith(
                "DutchAuctionFactory: only multi sign wallet",
            );
        });

        it("Should deploy", async () => {
            await helpers.mine(1);

            await hhDAuctionF.connect(multiSignWallet).deploy(1, 2, 4, 1);

            await expect((await hhDAuctionF.getAuctions()).length).to.equal(1);
        });

        it("Should get right auctions", async () => {
            const auctions = await hhDAuctionF.getAuctions();

            await expect(auctions.length).to.equal(1);
        });

        it("Should deploy one more auction", async () => {
            await helpers.mine(1);

            await hhDAuctionF.connect(multiSignWallet).deploy(1, 2, 4, 1);

            await expect((await hhDAuctionF.getAuctions()).length).to.equal(2);
        });

        it("Should get right auctionAt", async () => {
            const auctions = await hhDAuctionF.getAuctions();

            await expect(await hhDAuctionF.getAuctionAt(0)).to.equal(auctions[0]);
            await expect(await hhDAuctionF.getAuctionAt(1)).to.equal(auctions[1]);
        });
    });
});
