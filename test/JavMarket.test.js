const {expect} = require("chai");
const {ethers, upgrades} = require("hardhat")
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");


describe("JavMarket contract", () => {
    let hhJavMarket;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let erc20Token;
    let adminError;
    let nonZeroAddress;

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
        const javMarket = await ethers.getContractFactory("JavMarket");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        hhJavMarket = await upgrades.deployProxy(
            javMarket,
            [
                erc20Token.target,
                bot.address
            ],

            {
                initializer: "initialize",
            }
        );


        adminError = "JavMarket: only admin"

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

        it("Should set the _paused status", async () => {

            await expect(await hhJavMarket.paused()).to.equal(false);
        });

    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(
                hhJavMarket.connect(addr1).pause()
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set pause", async () => {
            await hhJavMarket.pause();

            await expect(await hhJavMarket.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(
                hhJavMarket.connect(addr1).unpause()
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set unpause", async () => {
            await hhJavMarket.unpause();

            await expect(await hhJavMarket.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavMarket.connect(addr1).setAdminAddress(owner.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the admin address", async () => {
            await hhJavMarket.setAdminAddress(owner.address);

            await expect(await hhJavMarket.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when set the bot address", async () => {
            await expect(
                hhJavMarket.connect(addr1).setBotAddress(bot.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the bot address", async () => {
            await hhJavMarket.setBotAddress(bot.address);

            await expect(await hhJavMarket.botAddress()).to.equal(bot.address);
        });

        it("Should revert when add token", async () => {
            await expect(
                hhJavMarket.connect(addr1).addToken(nonZeroAddress)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should add token", async () => {
            const idBefore = await hhJavMarket.currentTokenId()
            await hhJavMarket.addToken(nonZeroAddress);
            const id = await hhJavMarket.currentTokenId()

            await expect(await hhJavMarket.currentTokenId()).to.equal(idBefore + BigInt(1));
            await expect(await hhJavMarket.tokens(id)).to.equal(nonZeroAddress);
            await expect(await hhJavMarket.isActiveToken(id)).to.equal(true);
        });

        it("Should revert when remove token", async () => {
            await expect(
                hhJavMarket.connect(addr1).removeToken(15)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should remove token", async () => {
            const id = await hhJavMarket.currentTokenId()
            await hhJavMarket.removeToken(id);

            await expect(await hhJavMarket.isActiveToken(id)).to.equal(false);
        });

        it("Should revert when buy paused=true", async () => {
            await hhJavMarket.pause();

            await expect(
                hhJavMarket.connect(addr1).buy(15, 1)
            ).to.be.revertedWithCustomError(
                hhJavMarket, "EnforcedPause"
            );
            await hhJavMarket.unpause();

        });


        it("Should revert when buy token not active", async () => {
            const id = await hhJavMarket.currentTokenId()

            await expect(
                hhJavMarket.connect(addr1).buy(15, id)
            ).to.be.revertedWith(
                "JavMarket: token not active"
            );

        });

        it("Should revert when buy balanceOf < _amount", async () => {
            await hhJavMarket.addToken(nonZeroAddress);
            const id = await hhJavMarket.currentTokenId()

            await expect(
                hhJavMarket.connect(addr1).buy(15, id)
            ).to.be.revertedWith(
                "JavMarket: invalid amount"
            );

        });

        it("Should buy token", async () => {
            const amount = await ethers.parseEther("1");
            const id = await hhJavMarket.currentTokenId()

            await erc20Token.mint(addr1.address, amount)
            await erc20Token.connect(addr1).approve(hhJavMarket.target, amount);

            await hhJavMarket.connect(addr1).buy(amount, id);

            await expect(await erc20Token.balanceOf(bot.address)).to.equal(amount);
            await expect(await hhJavMarket.totalAmountByToken(id)).to.equal(amount);
            await expect(await hhJavMarket.totalOrdersByToken(id)).to.equal(1);
            await expect(await hhJavMarket.totalOrders()).to.equal(1);
        });

    });
});


