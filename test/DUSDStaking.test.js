const {expect} = require("chai");
const {ethers} = require("hardhat")
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");


describe("DUSDStaking contract", () => {
    let hhDUSDStaking;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let erc20Token;
    let adminError;

    async function deployTokenFixture() {
        const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
        erc20Token = await erc20ContractFactory.deploy(
            "MockERC20",
            "MOCK",
        );
        await erc20Token.waitForDeployment();
        return erc20Token
    }

    before(async () => {
        const dusdStaking = await ethers.getContractFactory("DUSDStaking");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        hhDUSDStaking = await dusdStaking.deploy();
        await hhDUSDStaking.initialize(
            erc20Token.target,
            bot.address,
        );


        adminError = "DUSDStaking: only admin"

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
            await expect(
                hhDUSDStaking.connect(addr1).pause()
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set pause", async () => {
            await hhDUSDStaking.pause();

            await expect(await hhDUSDStaking.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).unpause()
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set unpause", async () => {
            await hhDUSDStaking.unpause();

            await expect(await hhDUSDStaking.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).setAdminAddress(owner.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the admin address", async () => {
            await hhDUSDStaking.setAdminAddress(owner.address);

            await expect(await hhDUSDStaking.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when set the bot address", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).setBotAddress(bot.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the bot address", async () => {
            await hhDUSDStaking.setBotAddress(bot.address);

            await expect(await hhDUSDStaking.botAddress()).to.equal(bot.address);
        });

        it("Should revert when deposit paused=true", async () => {
            await hhDUSDStaking.pause();

            await expect(
                hhDUSDStaking.connect(addr1).deposit(15)
            ).to.be.revertedWith(
                "Pausable: paused"
            );
            await hhDUSDStaking.unpause();

        });

        it("Should deposit", async () => {
            const amount = ethers.parseEther("1");
            await erc20Token.mint(addr1.address, amount)
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, amount);
            const amountBefore = await erc20Token.balanceOf(bot.address)

            await hhDUSDStaking.connect(addr1).deposit(amount);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(0)
            await expect(await erc20Token.balanceOf(bot.address)).to.equal(amount + amountBefore)
            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(amount)

        });

        it("Should revert when updateInvestment onlyBot", async () => {
            const amount = ethers.parseEther("1");
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount
                },
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await expect(
                hhDUSDStaking.connect(addr1).updateInvestment(messageData)
            ).to.be.revertedWith(
                "DUSDStaking: only bot"
            );

        });

        it("Should updateInvestment - deposit > 0  investment = 0", async () => {
            const amount = ethers.parseEther("1");
            const userDepositBefore1 = await hhDUSDStaking.userDeposit(addr1.address)
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount
                },
            ]

            await hhDUSDStaking.connect(bot).updateInvestment(messageData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(userDepositBefore1- amount);
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(amount);

        });

        it("Should revert when updateInvestment - userInvestment > new userInvestmentAmount", async () => {
            const userInvestment = await hhDUSDStaking.userInvestment(addr1.address)
            const messageData = [
                {
                    user: addr1.address,
                    amount: userInvestment - ethers.parseEther("0.005")
                },
            ]

            await expect(
                hhDUSDStaking.connect(bot).updateInvestment(messageData)
            ).to.be.revertedWith(
                "DUSDStaking: invalid new investment amount on userInvestment"
            );

        });

        it("Should updateInvestment - reinvest, userDeposit=0", async () => {
            const amount = ethers.parseEther("1");
            const messageData = [
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await hhDUSDStaking.connect(bot).updateInvestment(messageData);

            await expect(await hhDUSDStaking.userDeposit(addr3.address)).to.equal(0);
            await expect(await hhDUSDStaking.userInvestment(addr3.address)).to.equal(amount);

        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment < deposit", async () => {
            const investmentAmount = ethers.parseEther("2");
            const depositAmount = ethers.parseEther("3");
            const amountBefore = await hhDUSDStaking.userInvestment(addr1.address);

            await erc20Token.mint(addr1.address, depositAmount)
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, depositAmount);
            await hhDUSDStaking.connect(addr1).deposit(depositAmount);
            const userDeposit = await hhDUSDStaking.userDeposit(addr1.address);

            const messageData = [
                {
                    user: addr1.address,
                    amount: investmentAmount
                },
            ]

            await hhDUSDStaking.connect(bot).updateInvestment(messageData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(userDeposit - (investmentAmount - amountBefore));
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(investmentAmount);

        });

        it("Should revert when updateInvestment - userDeposit < newUserInvestment - userInvestment", async () => {
            const userDeposit = await hhDUSDStaking.userDeposit(addr1.address)
            const userInvestment = await hhDUSDStaking.userInvestment(addr1.address)

            const messageData = [
                {
                    user: addr1.address,
                    amount: userDeposit + userInvestment + ethers.parseEther("1")
                },
            ]

            await expect(
                hhDUSDStaking.connect(bot).updateInvestment(messageData)
            ).to.be.revertedWith(
                "DUSDStaking: invalid new investment amount on userDeposit"
            );

        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment = deposit", async () => {
            const userInvestment = await hhDUSDStaking.userInvestment(addr1.address);
            const userDeposit = await hhDUSDStaking.userDeposit(addr1.address);
            const depositAmount = ethers.parseEther("3");
            const investmentAmount = userDeposit + userInvestment + depositAmount

            await erc20Token.mint(addr1.address, depositAmount)
            await erc20Token.connect(addr1).approve(hhDUSDStaking.target, depositAmount);

            await hhDUSDStaking.connect(addr1).deposit(depositAmount);

            const messageData = [
                {
                    user: addr1.address,
                    amount: investmentAmount
                },
            ]

            await hhDUSDStaking.connect(bot).updateInvestment(messageData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(0);
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(investmentAmount);
        });

        it("Should updateInvestment with deposit > new userInvestment ", async () => {
            const amount = ethers.parseEther("15");
            const newAmount = ethers.parseEther("5");
            const userInvestmentBefore = await hhDUSDStaking.userInvestment(addr3.address);

            await erc20Token.mint(addr3.address, amount);
            await erc20Token.connect(addr3).approve(hhDUSDStaking.target, amount);
            await hhDUSDStaking.connect(addr3).deposit(amount);

            const userDepositBefore = await hhDUSDStaking.userDeposit(addr3.address);

            const messageData = [
                {
                    user: addr3.address,
                    amount: newAmount
                },
            ]

            await hhDUSDStaking.connect(bot).updateInvestment(messageData);


            await expect(await hhDUSDStaking.userInvestment(addr3.address)).to.equal(newAmount);
            await expect(await hhDUSDStaking.userDeposit(addr3.address)).to.equal(userDepositBefore - (newAmount - userInvestmentBefore));

        });

        it("Should revert when request withdraw userInvestment[msg.sender] < _amount", async () => {
            const userInvestment = await hhDUSDStaking.userInvestment(addr3.address)
            await expect(
                hhDUSDStaking.connect(addr3).requestWithdraw(userInvestment + ethers.parseEther("2"))
            ).to.be.revertedWith(
                "DUSDStaking: invalid amount for withdraw"
            );
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
                    amount: amount
                },
                {
                    user: addr3.address,
                    amount: amount
                },
            ]

            await expect(
                hhDUSDStaking.connect(addr1).updateWithdraw(messageData)
            ).to.be.revertedWith(
                "DUSDStaking: only bot"
            );
        });

        it("Should revert when updateWithdraw - userRequestedWithdraw < _withdraw.amount", async () => {
            const amount = await hhDUSDStaking.userRequestedWithdraw(addr1.address);
            const messageData = [
                {
                    user: addr1.address,
                    amount: amount + ethers.parseEther("1")
                },
            ]

            await expect(
                hhDUSDStaking.connect(bot).updateWithdraw(messageData)
            ).to.be.revertedWith(
                "DUSDStaking: invalid claimable amount"
            );
        });

        it("Should updateWithdraw", async () => {
            await erc20Token.mint(bot.address, ethers.parseEther("5"))
            const amount = ethers.parseEther("1");
            const contractBalanceBefore = await erc20Token.balanceOf(hhDUSDStaking.target);
            const botBalanceBefore = await erc20Token.balanceOf(bot.address);
            const userRequestedWithdrawBefore = await hhDUSDStaking.userRequestedWithdraw(addr1.address);
            const userClaimableAmountBefore = await hhDUSDStaking.userClaimableAmount(addr1.address);
            const userInvestmentBefore = await hhDUSDStaking.userInvestment(addr1.address);

            const messageData = [
                {
                    user: addr1.address,
                    amount: amount
                },
            ]
            await erc20Token.connect(bot).approve(hhDUSDStaking.target, amount);
            await hhDUSDStaking.connect(bot).updateWithdraw(messageData);

            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(userInvestmentBefore - amount);
            await expect(await hhDUSDStaking.userRequestedWithdraw(addr1.address)).to.equal(userRequestedWithdrawBefore - amount);
            await expect(await hhDUSDStaking.userClaimableAmount(addr1.address)).to.equal(userClaimableAmountBefore + amount);
            await expect(await erc20Token.balanceOf(hhDUSDStaking.target)).to.equal(contractBalanceBefore + amount);
            await expect(await erc20Token.balanceOf(bot.address)).to.equal(botBalanceBefore - amount);


        });

        it("Should revert when withdraw _amount <= 0", async () => {
            await expect(
                hhDUSDStaking.connect(addr3).withdraw()
            ).to.be.revertedWith("DUSDStaking: invalid withdraw amount");

        });

        it("Should withdraw", async () => {
            const amount = await hhDUSDStaking.userClaimableAmount(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhDUSDStaking.target);
            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);

            await hhDUSDStaking.connect(addr1).withdraw();

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(userBalanceBefore + amount);
            await expect(await erc20Token.balanceOf(hhDUSDStaking.target)).to.equal(contractBalanceBefore - amount);
            await expect(await hhDUSDStaking.userClaimableAmount(addr1.address)).to.equal(0);


        });

        it("Should revert when withdraw paused=true", async () => {
            await hhDUSDStaking.pause()
            await expect(
                hhDUSDStaking.connect(addr1).withdraw()
            ).to.be.revertedWith("Pausable: paused");

        });

    });
});


