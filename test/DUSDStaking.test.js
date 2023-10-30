const {expect} = require("chai");
const {ethers} = require("hardhat")
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const EIP712Signer = require('./utils/EIP712');

const SIGNING_DOMAIN = "DUSD_STAKING";
const SIGNATURE_VERSION = "1";

const WithdrawMessageType = {
    WithdrawMessage: [
        { name: "user", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "salt", type: "uint256" }
    ]
};


describe("DUSDStaking contract", () => {
    let hhDUSDStaking;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let serviceSigner;
    let erc20Token;
    let eip712Signer;
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
            serviceSigner.address
        );

        eip712Signer = new EIP712Signer({
            signing_domain: SIGNING_DOMAIN,
            signature_version: SIGNATURE_VERSION,
            contract: hhDUSDStaking
        });

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

        it("Should revert when set the ServiceSigner address", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).setServiceSigner(serviceSigner.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the ServiceSigner address", async () => {
            await hhDUSDStaking.setServiceSigner(serviceSigner.address);
        });

        it("Should revert when deposit balanceOf(msg.sender) <= _amount", async () => {
            await expect(
                hhDUSDStaking.connect(addr1).deposit(15)
            ).to.be.revertedWith(
                "DUSDStaking: invalid amount"
            );

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

        it("Should updateInvestment - deposit > 0  investment = 0 ", async () => {
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

            await hhDUSDStaking.connect(bot).updateInvestment(messageData);

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(0);
            await expect(await hhDUSDStaking.userDeposit(addr3.address)).to.equal(0);
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(amount);
            await expect(await hhDUSDStaking.userInvestment(addr3.address)).to.equal(amount);

        });

        it("Should updateInvestment - deposit > 0  investment > 0  investment < deposit", async () => {
            const amountBefore = await hhDUSDStaking.userInvestment(addr1.address);
            const userDeposit = await hhDUSDStaking.userDeposit(addr1.address);
            const investmentAmount = ethers.parseEther("2");
            const depositAmount = ethers.parseEther("3");
            const investmentDeposit = userDeposit - (investmentAmount - amountBefore)

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

            await expect(await hhDUSDStaking.userDeposit(addr1.address)).to.equal(userDeposit - investmentDeposit);
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(investmentAmount);

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

        it("Should revert withdraw with claimMessage signed not by service signer", async () => {
            const withdrawMessage = {
                user: addr1.address,
                amount: ethers.parseEther("1"),
                salt: 5
            };

            const signedWithdrawMessage = await eip712Signer.signMessage(
                withdrawMessage,
                WithdrawMessageType,
                addr2
            );

            await expect(hhDUSDStaking.connect(addr1).withdraw(signedWithdrawMessage))
                .to.be.revertedWith("DUSDStaking: unknown signer");
        });

        it("Should revert withdraw -  front running", async function () {
            const withdrawMessage = {
                user: addr1.address,
                amount: ethers.parseEther("1"),
                salt: 10
            };

            const signedClaimMessage = await eip712Signer.signMessage(
                withdrawMessage,
                WithdrawMessageType,
                serviceSigner
            );

            await expect(hhDUSDStaking.connect(addr2).withdraw(signedClaimMessage))
                .to.be.revertedWith("DUSDStaking: wrong caller");
        });

        it("Should withdraw", async function () {
            const amount = ethers.parseEther("1");
            const investmentBefore = await hhDUSDStaking.userInvestment(addr1.address)
            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);

            await erc20Token.mint(hhDUSDStaking.target, amount);

            const contractBalance = await erc20Token.balanceOf(hhDUSDStaking.target);

            const withdrawMessage = {
                user: addr1.address,
                amount: amount,
                salt: 5
            };

            const signedWithdrawMessage = await eip712Signer.signMessage(
                withdrawMessage,
                WithdrawMessageType,
                serviceSigner
            );

            await hhDUSDStaking.connect(addr1).withdraw(signedWithdrawMessage);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(userBalanceBefore + amount);
            await expect(await erc20Token.balanceOf(hhDUSDStaking.target)).to.equal(contractBalance - amount);
            await expect(await hhDUSDStaking.userInvestment(addr1.address)).to.equal(investmentBefore - amount);
        });

        it("Should revert withdraw for already withdrawn", async function () {
            const withdrawMessage = {
                user: addr1.address,
                amount: ethers.parseEther("1"),
                salt: 5
            };

            const signedWithdrawMessage = await eip712Signer.signMessage(
                withdrawMessage,
                WithdrawMessageType,
                serviceSigner
            );

            await expect(hhDUSDStaking.connect(addr1).withdraw(signedWithdrawMessage))
                .to.be.revertedWith("DUSDStaking: already withdrawn");
        });

        it("Should revert when withdraw paused=true", async () => {
            await hhDUSDStaking.pause()
            const withdrawMessage = {
                user: addr1.address,
                amount: ethers.parseEther("1"),
                salt: 5
            };

            const signedWithdrawMessage = await eip712Signer.signMessage(
                withdrawMessage,
                WithdrawMessageType,
                serviceSigner
            );

            await expect(
                hhDUSDStaking.connect(addr1).withdraw(signedWithdrawMessage)
            ).to.be.revertedWith(
                "Pausable: paused"
            );

        });

    });
});


