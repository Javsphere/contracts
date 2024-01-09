const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR } = require("./common/constanst");
const { deployTokenFixture } = require("./common/mocks");

describe("JavMarket contract", () => {
    let hhJavMarket;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let treasury;
    let erc20Token;
    let nonZeroAddress;
    let fee;

    before(async () => {
        const javMarket = await ethers.getContractFactory("JavMarket");
        [owner, addr1, addr2, addr3, bot, treasury, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        fee = 10;

        hhJavMarket = await upgrades.deployProxy(
            javMarket,
            [erc20Token.target, bot.address, treasury.address, fee],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavMarket.owner()).to.equal(owner.address);
        });

        it("Should set the right token", async () => {
            await expect(await hhJavMarket.dusdToken()).to.equal(erc20Token.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavMarket.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right bot address", async () => {
            await expect(await hhJavMarket.botAddress()).to.equal(bot.address);
        });

        it("Should set the right treasuryAddress address", async () => {
            await expect(await hhJavMarket.treasuryAddress()).to.equal(treasury.address);
        });

        it("Should set the right fee", async () => {
            await expect(await hhJavMarket.fee()).to.equal(fee);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavMarket.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavMarket.connect(addr1).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhJavMarket.pause();

            await expect(await hhJavMarket.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavMarket.connect(addr1).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhJavMarket.unpause();

            await expect(await hhJavMarket.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavMarket.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavMarket.setAdminAddress(owner.address);

            await expect(await hhJavMarket.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when set the bot address", async () => {
            await expect(hhJavMarket.connect(addr1).setBotAddress(bot.address)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should set the bot address", async () => {
            await hhJavMarket.setBotAddress(bot.address);

            await expect(await hhJavMarket.botAddress()).to.equal(bot.address);
        });

        it("Should revert when set the treasury address", async () => {
            await expect(
                hhJavMarket.connect(addr1).setTreasuryAddress(bot.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the treasury address", async () => {
            await hhJavMarket.setTreasuryAddress(treasury.address);

            await expect(await hhJavMarket.treasuryAddress()).to.equal(treasury.address);
        });

        it("Should revert when set fee", async () => {
            await expect(hhJavMarket.connect(addr1).setFee(10)).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set fee", async () => {
            fee = 100;
            await hhJavMarket.setFee(fee);

            await expect(await hhJavMarket.fee()).to.equal(fee);
        });

        it("Should revert when buyToken paused=true", async () => {
            await hhJavMarket.pause();

            await expect(
                hhJavMarket.connect(addr1).buyToken(15, 1, 1, true, 1),
            ).to.be.revertedWithCustomError(hhJavMarket, "EnforcedPause");
            await hhJavMarket.unpause();
        });

        it("Should revert when buy balanceOf < _amount", async () => {
            await expect(hhJavMarket.connect(addr1).buyToken(15, 1, 1, true, 1)).to.be.revertedWith(
                "JavMarket: invalid amount",
            );
        });

        it("Should buy token", async () => {
            const amount = await ethers.parseEther("1");
            const id = 1;
            const feeAmount = (amount * BigInt(fee)) / BigInt(1000);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavMarket.target);

            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhJavMarket.target, amount);

            await hhJavMarket.connect(addr1).buyToken(amount, id, 1, true, 1);

            await expect(await erc20Token.balanceOf(treasury.address)).to.equal(feeAmount);
            await expect(await erc20Token.balanceOf(hhJavMarket.target)).to.equal(
                contractBalanceBefore + amount - feeAmount,
            );
            await expect(await hhJavMarket.totalAmountByToken(id)).to.equal(amount - feeAmount);
            await expect(await hhJavMarket.totalOrdersByToken(id)).to.equal(1);
            await expect(await hhJavMarket.totalOrders()).to.equal(1);
            await expect(await hhJavMarket.totalAmount()).to.equal(amount - feeAmount);
        });

        it("Should revert when emitOrderExecuted", async () => {
            await expect(
                hhJavMarket.connect(addr1).emitOrderExecuted(1, addr1.address, 1, 2, 3, true, 1),
            ).to.be.revertedWith("JavMarket: only bot");
        });

        it("Should emitOrderExecuted", async () => {
            await expect(
                hhJavMarket.connect(bot).emitOrderExecuted(1, addr1.address, 1, 2, 3, true, 1),
            )
                .to.emit(hhJavMarket, "OrderExecuted")
                .withArgs(1, addr1.address, 1, 2, 3, true, 1, 1);
        });

        it("Should revert when withdraw - only bot error", async () => {
            await expect(hhJavMarket.connect(addr1).withdraw(1)).to.be.revertedWith(
                "JavMarket: only bot",
            );
        });

        it("Should revert when withdraw - invalid amount", async () => {
            await expect(
                hhJavMarket.connect(bot).withdraw(ethers.parseEther("5")),
            ).to.be.revertedWith("JavMarket: invalid amount");
        });

        it("Should withdraw", async () => {
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavMarket.target);
            const botBalanceBefore = await erc20Token.balanceOf(bot.address);

            await hhJavMarket.connect(bot).withdraw(contractBalanceBefore);

            await expect(await erc20Token.balanceOf(hhJavMarket.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(bot.address)).to.be.equal(
                botBalanceBefore + contractBalanceBefore,
            );
        });
    });
});
