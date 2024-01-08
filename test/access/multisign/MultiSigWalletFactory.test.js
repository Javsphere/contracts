const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("MultiSigWalletFactory contract", () => {
    let hhMultiSigWalletFactory;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let adminError;

    before(async () => {
        const multiSigWalletFactory = await ethers.getContractFactory("MultiSigWalletFactory");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;

        hhMultiSigWalletFactory = await upgrades.deployProxy(
            multiSigWalletFactory,
            [],

            {
                initializer: "initialize",
            },
        );

        adminError = "BaseUpgradable: only admin";
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhMultiSigWalletFactory.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhMultiSigWalletFactory.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhMultiSigWalletFactory.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhMultiSigWalletFactory.connect(addr1).pause()).to.be.revertedWith(
                adminError,
            );
        });

        it("Should set pause", async () => {
            await hhMultiSigWalletFactory.pause();

            await expect(await hhMultiSigWalletFactory.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhMultiSigWalletFactory.connect(addr1).unpause()).to.be.revertedWith(
                adminError,
            );
        });

        it("Should set unpause", async () => {
            await hhMultiSigWalletFactory.unpause();

            await expect(await hhMultiSigWalletFactory.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhMultiSigWalletFactory.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(adminError);
        });

        it("Should set the admin address", async () => {
            await hhMultiSigWalletFactory.setAdminAddress(owner.address);

            await expect(await hhMultiSigWalletFactory.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when create wallet", async () => {
            await expect(
                hhMultiSigWalletFactory.connect(addr1).create([owner.address], 1),
            ).to.be.revertedWith(adminError);
        });

        it("Should create wallet", async () => {
            const owners = [addr1.address, addr2.address];
            const required = 2;

            await hhMultiSigWalletFactory.create(owners, required);

            await expect(
                await hhMultiSigWalletFactory.getInstantiationCount(owner.address),
            ).to.be.equal(1);
        });

        it("Should getInstantiationCount", async () => {
            await expect(
                await hhMultiSigWalletFactory.getInstantiationCount(owner.address),
            ).to.be.equal(1);
            await expect(
                await hhMultiSigWalletFactory.getInstantiationCount(addr2.address),
            ).to.be.equal(0);
        });
    });
});
