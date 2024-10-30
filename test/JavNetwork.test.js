const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR, MANAGER_ERROR } = require("./common/constanst");

describe("JavNetwork contract", () => {
    let hhJavNetwork;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;

    before(async () => {
        const javNetwork = await ethers.getContractFactory("JavNetwork");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();

        hhJavNetwork = await upgrades.deployProxy(
            javNetwork,
            [bot.address],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavNetwork.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavNetwork.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right bot address", async () => {
            await expect(await hhJavNetwork.botAddress()).to.equal(bot.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavNetwork.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavNetwork.connect(addr1).pause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set pause", async () => {
            await hhJavNetwork.pause();

            await expect(await hhJavNetwork.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavNetwork.connect(addr1).unpause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set unpause", async () => {
            await hhJavNetwork.unpause();

            await expect(await hhJavNetwork.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavNetwork.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavNetwork.setAdminAddress(owner.address);

            await expect(await hhJavNetwork.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when set the bot address", async () => {
            await expect(hhJavNetwork.connect(addr1).setBotAddress(bot.address)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should set the bot address", async () => {
            await hhJavNetwork.setBotAddress(bot.address);

            await expect(await hhJavNetwork.botAddress()).to.equal(bot.address);
        });

        it("Should revert when saveCID not bot", async () => {
            await expect(hhJavNetwork.connect(addr1).saveCID("t", "t")).to.be.revertedWith(
                "JavNetwork: only bot",
            );
        });

        it("Should saveCID ", async () => {
            const key = "test_key";
            const value = "frwklghniu23erhtfn24eionweofefg3ewrt234";

            await hhJavNetwork.connect(bot).saveCID(key, value);

            await expect(await hhJavNetwork.getCID(key)).to.be.equal(value);
        });
    });
});
