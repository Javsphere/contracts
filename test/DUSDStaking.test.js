const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { MANAGER_ERROR, ADMIN_ERROR } = require("./common/constanst");
const { deployTokenFixture } = require("./common/mocks");

describe("DUSDStaking contract", () => {
    let hhDUSDStaking;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let erc20Token;

    before(async () => {
        const dusdStaking = await ethers.getContractFactory("DUSDStaking");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        hhDUSDStaking = await upgrades.deployProxy(
            dusdStaking,
            [erc20Token.target, bot.address],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhDUSDStaking.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {
            await expect(await hhDUSDStaking.token()).to.equal(erc20Token.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhDUSDStaking.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right bot address", async () => {
            await expect(await hhDUSDStaking.botAddress()).to.equal(bot.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhDUSDStaking.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhDUSDStaking.connect(addr1).pause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set pause", async () => {
            await hhDUSDStaking.pause();

            await expect(await hhDUSDStaking.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhDUSDStaking.connect(addr1).unpause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set unpause", async () => {
            await hhDUSDStaking.unpause();

            await expect(await hhDUSDStaking.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhDUSDStaking.setAdminAddress(owner.address);

            await expect(await hhDUSDStaking.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when set the bot address", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).setBotAddress(bot.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the bot address", async () => {
            await hhDUSDStaking.setBotAddress(bot.address);

            await expect(await hhDUSDStaking.botAddress()).to.equal(bot.address);
        });

        it("Should revert when deposit paused=true", async () => {
            await hhDUSDStaking.pause();

            await expect(hhDUSDStaking.connect(addr1).deposit(15)).to.be.revertedWithCustomError(
                hhDUSDStaking,
                "EnforcedPause",
            );
            await hhDUSDStaking.unpause();
        });

        it("Should deposit", async () => {
            const amount = ethers.parseEther("1");
            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, amount);
            const amountBefore = await erc20Token.balanceOf(bot.address);

            await hhDUSDStaking.connect(addr1).deposit(amount);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(0);
            await expect(await erc20Token.balanceOf(bot.address)).to.equal(amount + amountBefore);
            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(amount);
        });

        it("Should revert when updateInvestment onlyBot", async () => {
            const amount = ethers.parseEther("1");
            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: amount,
                },
                {
                    user: addr3.address,
                    amount: amount,
                },
            ];

            const messageRewardsData = [
                {
                    user: addr1.address,
                    amount: amount,
                },
                {
                    user: addr3.address,
                    amount: amount,
                },
            ];

            await expect(
                hhDUSDStaking
                    .connect(addr1)
                    .updateInvestment(messageDepositData, messageRewardsData),
            ).to.be.revertedWith("DUSDStaking: only bot");
        });

        it("Should revert when updateInvestment userDeposit < _depositInfo[i].amount", async () => {
            const amount = ethers.parseEther("1");
            const userDeposit = await hhDUSDStaking.userDeposit(addr1.address);
            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: userDeposit + amount,
                },
            ];

            const messageRewardsData = [];

            await expect(
                hhDUSDStaking.connect(bot).updateInvestment(messageDepositData, messageRewardsData),
            ).to.be.revertedWith("DUSDStaking: invalid deposit info");
        });

        it("Should updateInvestment - deposit > 0  investment = 0", async () => {
            const amount = ethers.parseEther("1");
            const userDepositBefore1 = await hhDUSDStaking.userDeposit(addr1.address);
            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: amount,
                },
            ];
            const messageRewardsData = [];

            await hhDUSDStaking
                .connect(bot)
                .updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(
                userDepositBefore1 - amount,
            );
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(amount);
        });

        it("Should updateInvestment - reinvest, userDeposit=0", async () => {
            const amount = ethers.parseEther("1");
            const investmentBefore = await hhDUSDStaking.userInvestment(addr3.address);
            const messageDepositData = [];
            const messageRewardsData = [
                {
                    user: addr3.address,
                    amount: amount,
                },
            ];

            await hhDUSDStaking
                .connect(bot)
                .updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDUSDStaking.userDeposit(addr3.address)).to.equal(0);
            await expect(await hhDUSDStaking.userInvestment(addr3.address)).to.equal(
                investmentBefore + amount,
            );
        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment < deposit with rewards", async () => {
            const investmentAmount = ethers.parseEther("2");
            const rewardsAmount = ethers.parseEther("0.005");
            const depositAmount = ethers.parseEther("3");
            const amountBefore = await hhDUSDStaking.userInvestment(addr1.address);

            await erc20Token.mint(addr1.address, depositAmount);
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, depositAmount);
            await hhDUSDStaking.connect(addr1).deposit(depositAmount);
            const userDepositBefore = await hhDUSDStaking.userDeposit(addr1.address);

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: investmentAmount,
                },
            ];
            const messageRewardsData = [
                {
                    user: addr1.address,
                    amount: rewardsAmount,
                },
            ];

            await hhDUSDStaking
                .connect(bot)
                .updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(
                userDepositBefore - investmentAmount,
            );
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(
                amountBefore + investmentAmount + rewardsAmount,
            );
        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment = deposit", async () => {
            const userInvestmentBefore = await hhDUSDStaking.userInvestment(addr1.address);
            const userDepositBefore = await hhDUSDStaking.userDeposit(addr1.address);
            const depositAmount = ethers.parseEther("1");
            const investmentAmount = userDepositBefore + depositAmount;

            await erc20Token.mint(addr1.address, depositAmount);
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, depositAmount);

            await hhDUSDStaking.connect(addr1).deposit(depositAmount);

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: investmentAmount,
                },
            ];
            const messageRewardsData = [];

            await hhDUSDStaking
                .connect(bot)
                .updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(
                userDepositBefore + depositAmount - investmentAmount,
            );
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(
                userInvestmentBefore + investmentAmount,
            );
        });

        it("Should updateInvestment with deposit > new userInvestment ", async () => {
            const userInvestmentBefore = await hhDUSDStaking.userInvestment(addr1.address);
            const userDepositBefore = await hhDUSDStaking.userDeposit(addr1.address);
            const depositAmount = ethers.parseEther("1");
            const investmentAmount = userDepositBefore;

            await erc20Token.mint(addr1.address, depositAmount);
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, depositAmount);

            await hhDUSDStaking.connect(addr1).deposit(depositAmount);

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: investmentAmount,
                },
            ];
            const messageRewardsData = [];

            await hhDUSDStaking
                .connect(bot)
                .updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(
                userDepositBefore + depositAmount - investmentAmount,
            );
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(
                userInvestmentBefore + investmentAmount,
            );
        });

        it("Should updateInvestment with  diff users", async () => {
            // user1 - investment = deposit
            // user2 - investment = part of deposit
            // user3 - only rewards
            // user4 - investment = part of deposit, + rewards
            const userInvestmentBefore1 = await hhDUSDStaking.userInvestment(addr1.address);
            const userInvestmentBefore2 = await hhDUSDStaking.userInvestment(addr2.address);
            const userInvestmentBefore3 = await hhDUSDStaking.userInvestment(addr3.address);
            const userInvestmentBefore4 = await hhDUSDStaking.userInvestment(owner.address);
            const rewardsAmount3 = ethers.parseEther("0.00006");
            const depositAmount1 = ethers.parseEther("0.5");
            const depositAmount2 = ethers.parseEther("1.7");
            const depositAmount4 = ethers.parseEther("2");
            const investmentAmount2 = depositAmount2 - ethers.parseEther("0.3");
            const investmentAmount4 = depositAmount4 - ethers.parseEther("1.3");
            const rewardsAmount4 = ethers.parseEther("0.00009");

            await erc20Token.mint(addr1.address, depositAmount1);
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, depositAmount1);
            await hhDUSDStaking.connect(addr1).deposit(depositAmount1);
            await erc20Token.mint(addr2.address, depositAmount2);
            await erc20Token.connect(addr2).approve(hhDUSDStaking.target, depositAmount2);
            await hhDUSDStaking.connect(addr2).deposit(depositAmount2);
            await erc20Token.mint(owner.address, depositAmount4);
            await erc20Token.connect(owner).approve(hhDUSDStaking.target, depositAmount4);
            await hhDUSDStaking.connect(owner).deposit(depositAmount4);

            const userDepositBefore1 = await hhDUSDStaking.userDeposit(addr1.address);
            const userDepositBefore2 = await hhDUSDStaking.userDeposit(addr2.address);
            const userDepositBefore3 = await hhDUSDStaking.userDeposit(addr3.address);
            const userDepositBefore4 = await hhDUSDStaking.userDeposit(owner.address);

            const messageDepositData = [
                {
                    user: addr1.address,
                    amount: userDepositBefore1,
                },
                {
                    user: addr2.address,
                    amount: investmentAmount2,
                },
                {
                    user: owner.address,
                    amount: investmentAmount4,
                },
            ];
            const messageRewardsData = [
                {
                    user: addr3.address,
                    amount: rewardsAmount3,
                },
                {
                    user: owner.address,
                    amount: rewardsAmount4,
                },
            ];

            await hhDUSDStaking
                .connect(bot)
                .updateInvestment(messageDepositData, messageRewardsData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(0);
            await expect(await hhDUSDStaking.userDeposit(addr2.address)).to.equal(
                userDepositBefore2 - investmentAmount2,
            );
            await expect(await hhDUSDStaking.userDeposit(addr3.address)).to.equal(
                userDepositBefore3,
            );
            await expect(await hhDUSDStaking.userDeposit(owner.address)).to.equal(
                userDepositBefore4 - investmentAmount4,
            );
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(
                userInvestmentBefore1 + userDepositBefore1,
            );
            await expect(await hhDUSDStaking.userInvestment(addr2.address)).to.equal(
                userInvestmentBefore2 + investmentAmount2,
            );
            await expect(await hhDUSDStaking.userInvestment(addr3.address)).to.equal(
                userInvestmentBefore3 + rewardsAmount3,
            );
            await expect(await hhDUSDStaking.userInvestment(owner.address)).to.equal(
                userInvestmentBefore4 + investmentAmount4 + rewardsAmount4,
            );
        });

        it("Should revert when request withdraw userInvestment[msg.sender] < _amount", async () => {
            const userInvestment = await hhDUSDStaking.userInvestment(addr3.address);
            await expect(
                hhDUSDStaking
                    .connect(addr3)
                    .requestWithdraw(userInvestment + ethers.parseEther("2")),
            ).to.be.revertedWith("DUSDStaking: invalid amount for withdraw");
        });

        it("Should create request withdraw ", async () => {
            const amount = ethers.parseEther("1");
            await hhDUSDStaking.connect(addr1).requestWithdraw(amount);

            await expect(await hhDUSDStaking.userRequestedWithdraw(addr1.address)).to.equal(amount);
        });

        it("Should revert when updateWithdraw onlyBot", async () => {
            const amount = ethers.parseEther("1");
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount,
                },
                {
                    user: addr3.address,
                    amount: amount,
                },
            ];

            await expect(
                hhDUSDStaking.connect(addr1).updateWithdraw(messageData),
            ).to.be.revertedWith("DUSDStaking: only bot");
        });

        it("Should revert when updateWithdraw - userRequestedWithdraw < _withdraw.amount", async () => {
            const amount = await hhDUSDStaking.userRequestedWithdraw(addr1.address);
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount + ethers.parseEther("1"),
                },
            ];

            await expect(hhDUSDStaking.connect(bot).updateWithdraw(messageData)).to.be.revertedWith(
                "DUSDStaking: invalid claimable amount",
            );
        });

        it("Should updateWithdraw", async () => {
            await erc20Token.mint(bot.address, ethers.parseEther("5"));
            const amount = ethers.parseEther("1");
            const userRequestedWithdrawBefore = await hhDUSDStaking.userRequestedWithdraw(
                addr1.address,
            );
            const userClaimableAmountBefore = await hhDUSDStaking.userClaimableAmount(
                addr1.address,
            );
            const userInvestmentBefore = await hhDUSDStaking.userInvestment(addr1.address);

            const messageData = [
                {
                    user: addr1.address,
                    amount: amount,
                },
            ];
            await erc20Token.connect(bot).approve(hhDUSDStaking.target, amount);
            await hhDUSDStaking.connect(bot).updateWithdraw(messageData);

            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(
                userInvestmentBefore - amount,
            );
            await expect(await hhDUSDStaking.userRequestedWithdraw(addr1.address)).to.equal(
                userRequestedWithdrawBefore - amount,
            );
            await expect(await hhDUSDStaking.userClaimableAmount(addr1.address)).to.equal(
                userClaimableAmountBefore + amount,
            );
        });

        it("Should revert when withdraw _amount <= 0", async () => {
            await expect(hhDUSDStaking.connect(addr3).withdraw()).to.be.revertedWith(
                "DUSDStaking: invalid withdraw amount",
            );
        });

        it("Should revert when withdraw _token.balanceOf < _amount", async () => {
            await expect(hhDUSDStaking.connect(addr1).withdraw()).to.be.revertedWith(
                "DUSDStaking: not enough tokens",
            );
        });

        it("Should withdraw", async () => {
            const amount = await hhDUSDStaking.userClaimableAmount(addr1.address);
            await erc20Token.mint(hhDUSDStaking.target, amount);
            const contractBalanceBefore = await erc20Token.balanceOf(hhDUSDStaking.target);
            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);

            await hhDUSDStaking.connect(addr1).withdraw();

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(
                userBalanceBefore + amount,
            );
            await expect(await erc20Token.balanceOf(hhDUSDStaking.target)).to.equal(
                contractBalanceBefore - amount,
            );
            await expect(await hhDUSDStaking.userClaimableAmount(addr1.address)).to.equal(0);
        });

        it("Should revert when withdraw paused=true", async () => {
            await hhDUSDStaking.pause();
            await expect(hhDUSDStaking.connect(addr1).withdraw()).to.be.revertedWithCustomError(
                hhDUSDStaking,
                "EnforcedPause",
            );
        });
    });
});
