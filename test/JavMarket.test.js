const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR, MANAGER_ERROR } = require("./common/constanst");
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
            [[erc20Token.target], bot.address, treasury.address, fee],

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
            await expect((await hhJavMarket.getTokens())[0]).to.equal(erc20Token.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavMarket.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right bot address", async () => {
            await expect((await hhJavMarket.getBotsAddresses())[0]).to.equal(bot.address);
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
            await expect(hhJavMarket.connect(addr1).pause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set pause", async () => {
            await hhJavMarket.pause();

            await expect(await hhJavMarket.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavMarket.connect(addr1).unpause()).to.be.revertedWith(MANAGER_ERROR);
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

        it("Should revert when addBotAddress", async () => {
            await expect(hhJavMarket.connect(addr1).addBotAddress(bot.address)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should addBotAddress", async () => {
            await hhJavMarket.addBotAddress(addr2.address);

            const addresses = await hhJavMarket.getBotsAddresses();

            await expect(addresses.length).to.equal(2);
            await expect(addresses[0]).to.equal(bot.address);
            await expect(addresses[1]).to.equal(addr2.address);
        });

        it("Should revert when removeBotAddress", async () => {
            await expect(
                hhJavMarket.connect(addr1).removeBotAddress(bot.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should removeBotAddress", async () => {
            await hhJavMarket.removeBotAddress(addr2.address);

            const addresses = await hhJavMarket.getBotsAddresses();

            await expect(addresses.length).to.equal(1);
            await expect(addresses[0]).to.equal(bot.address);
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
                hhJavMarket.connect(addr1).tradeToken(0, 15, "1", 1, true, 1),
            ).to.be.revertedWithCustomError(hhJavMarket, "EnforcedPause");
            await hhJavMarket.unpause();
        });

        it("Should revert when buy balanceOf < _amount", async () => {
            await expect(
                hhJavMarket.connect(addr1).tradeToken(0, 15, "1", 1, true, 1),
            ).to.be.revertedWith("JavMarket: invalid amount");
        });

        it("Should buy token", async () => {
            const amount = await ethers.parseEther("1");
            const id = "test";
            const feeAmount = (amount * BigInt(fee)) / BigInt(1000);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavMarket.target);

            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhJavMarket.target, amount);

            await hhJavMarket.connect(addr1).tradeToken(0, amount, id, 1, true, 1);

            await expect(await erc20Token.balanceOf(treasury.address)).to.equal(feeAmount);
            await expect(await erc20Token.balanceOf(hhJavMarket.target)).to.equal(
                contractBalanceBefore + amount - feeAmount,
            );
            await expect(await hhJavMarket.totalOrders()).to.equal(1);
            await expect(await hhJavMarket.totalAmount()).to.equal(amount - feeAmount);
        });

        it("Should revert when emitOrderExecuted - not bot", async () => {
            const info = [
                {
                    userAddress: addr1.address,
                    id: 1,
                    tradeTokenId: 0,
                    tokenId: "1",
                    buyingType: 1,
                    amount: 2,
                    price: 3,
                    receiveAmount: 0,
                    isBuy: true,
                    tokenName: "test",
                },
            ];

            await expect(hhJavMarket.connect(addr1).emitOrderExecuted(info)).to.be.revertedWith(
                "JavMarket: only bot",
            );
        });

        it("Should revert when emitOrderExecuted - invalid order id", async () => {
            const info = [
                {
                    userAddress: addr1.address,
                    id: 500,
                    tradeTokenId: 0,
                    tokenId: "1",
                    buyingType: 1,
                    amount: 2,
                    price: 3,
                    receiveAmount: 0,
                    isBuy: true,
                    tokenName: "test",
                },
            ];

            await expect(hhJavMarket.connect(bot).emitOrderExecuted(info)).to.be.revertedWith(
                "JavMarket: order already executed or not created",
            );
        });

        it("Should emitOrderExecuted", async () => {
            const userAddress = addr1.address;
            const id = 1;
            const tokenId = "1";
            const buyingType = 1;
            const amount = 100;
            const price = 3;
            const receiveAmount = 30;
            const isBuy = true;
            const tokenName = "test";
            const info = [
                {
                    userAddress: userAddress,
                    id: id,
                    tradeTokenId: 0,
                    tokenId: tokenId,
                    buyingType: buyingType,
                    amount: amount,
                    price: price,
                    receiveAmount: receiveAmount,
                    isBuy: isBuy,
                    tokenName: tokenName,
                },
            ];

            await expect(hhJavMarket.connect(bot).emitOrderExecuted(info))
                .to.emit(hhJavMarket, "OrderExecuted")
                .withArgs(
                    id,
                    userAddress,
                    amount,
                    receiveAmount,
                    tokenId,
                    buyingType,
                    isBuy,
                    price,
                    tokenName,
                    1,
                );
        });

        it("Should revert when withdraw - only bot error", async () => {
            await expect(
                hhJavMarket.connect(addr1).withdraw(0, 1, addr3.address),
            ).to.be.revertedWith("JavMarket: only bot");
        });

        it("Should revert when withdraw - invalid amount", async () => {
            await expect(
                hhJavMarket.connect(bot).withdraw(0, ethers.parseEther("5"), addr3.address),
            ).to.be.revertedWith("JavMarket: invalid amount");
        });

        it("Should withdraw", async () => {
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavMarket.target);
            const balanceBefore = await erc20Token.balanceOf(addr3.address);

            await hhJavMarket.connect(bot).withdraw(0, contractBalanceBefore, addr3.address);

            await expect(await erc20Token.balanceOf(hhJavMarket.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(addr3.address)).to.be.equal(
                balanceBefore + contractBalanceBefore,
            );
        });
    });
});
