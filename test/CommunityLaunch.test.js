const {expect} = require("chai");
const {ethers, upgrades} = require("hardhat")
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {ADMIN_ERROR} = require("./common/constanst");


describe("CommunityLaunch contract", () => {
    let hhCommunityLaunch;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let multiSignWallet;
    let erc20Token;
    let saleActiveError;
    let startTokenPrice;
    let incPricePerBlock;
    let startBlock;

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
        const communityLaunch = await ethers.getContractFactory("CommunityLaunch");
        [owner, addr1, addr2, admin, multiSignWallet, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        startTokenPrice = ethers.parseEther("0.02")
        incPricePerBlock = ethers.parseEther("0.0000002")

        hhCommunityLaunch = await upgrades.deployProxy(
            communityLaunch,
            [
                await erc20Token.getAddress(),
                multiSignWallet.address,
                startTokenPrice,
                incPricePerBlock,
            ],

            {
                initializer: "initialize",
            }
        );

        saleActiveError = "CommunityLaunch: contract is not available right now"

    });

    describe("Deployment", () => {

        it("Should set the right owner address", async () => {

            await expect(await hhCommunityLaunch.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {

            await expect(await hhCommunityLaunch.token()).to.equal(erc20Token.target);
        });

        it("Should set the right multi sign wallet address", async () => {

            await expect(await hhCommunityLaunch.multiSignWallet()).to.equal(multiSignWallet.address);
        });

        it("Should set the right admin address", async () => {

            await expect(await hhCommunityLaunch.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right isSaleActive flag", async () => {

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(false);
        });

        it("Should set the right startTokenPrice", async () => {

            await expect(await hhCommunityLaunch.startTokenPrice()).to.equal(startTokenPrice);
        });

        it("Should set the right incPricePerBlock", async () => {

            await expect(await hhCommunityLaunch.incPricePerBlock()).to.equal(incPricePerBlock);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("20")

            await erc20Token.mint(hhCommunityLaunch.target, tokenAmounts);
            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.equal(tokenAmounts);
        });


    });

    describe("Transactions", () => {
        it("Should revert when set the admin address", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setAdminAddress(admin.address)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the admin address", async () => {
            await hhCommunityLaunch.setAdminAddress(admin.address);

            await expect(await hhCommunityLaunch.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when set the multi sign wallet address", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setMultiSignWalletAddress(admin.address)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the multi sign wallet address", async () => {
            await hhCommunityLaunch.setMultiSignWalletAddress(multiSignWallet.address);

            await expect(await hhCommunityLaunch.multiSignWallet()).to.equal(multiSignWallet.address);
        });

        it("Should revert when set setSaleActive", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setSaleActive(true)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the setSaleActive", async () => {
            await hhCommunityLaunch.setSaleActive(true);

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(true);
        });

        it("Should revert when set the setstartTokenPrice", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setStartTokenPrice(ethers.parseEther("0.0005"))
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the setStartTokenPrice", async () => {
            startTokenPrice = ethers.parseEther("0.05")
            await hhCommunityLaunch.setStartTokenPrice(startTokenPrice);

            await expect(await hhCommunityLaunch.startTokenPrice()).to.equal(startTokenPrice);
        });

        it("Should revert when set the setStartBlock", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setStartBlock(1)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the setStartBlock", async () => {
            startBlock = await helpers.time.latestBlock() + 50;
            await hhCommunityLaunch.setStartBlock(startBlock);

            await expect(await hhCommunityLaunch.startBlock()).to.equal(startBlock);
        });

        it("Should revert when set the setIncPricePerBlock", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setIncPricePerBlock(1)
            ).to.be.revertedWith(
                ADMIN_ERROR
            );

        });

        it("Should set the setIncPricePerBlock", async () => {
            incPricePerBlock = ethers.parseEther("0.0000005")

            await hhCommunityLaunch.setIncPricePerBlock(incPricePerBlock);

            await expect(await hhCommunityLaunch.incPricePerBlock()).to.equal(incPricePerBlock);
        });

        it("Should get the right tokenPrice when block.number > startBlock", async () => {
            const tokenPrice = await hhCommunityLaunch.startTokenPrice();

            await expect(await hhCommunityLaunch.tokenPrice()).to.equal(tokenPrice);
        });

        it("Should get the right tokenPrice when block.number < startBlock", async () => {
            await helpers.mine(100)

            const currentBlock = BigInt(await helpers.time.latestBlock());
            const price = (currentBlock - BigInt(startBlock)) * incPricePerBlock + startTokenPrice;

            await expect(await hhCommunityLaunch.tokenPrice()).to.equal(price);

            await hhCommunityLaunch.setStartBlock(currentBlock + BigInt(10));
        });

        it("Should get the right tokensBalance", async () => {

            await expect(await hhCommunityLaunch.tokensBalance()).to.equal(ethers.parseEther("20"));
        });

        it("Should revert when buy with isSaleActive = false", async () => {
            await hhCommunityLaunch.setSaleActive(false);

            await expect(
                hhCommunityLaunch.connect(addr1).buy({
                    value: ethers.parseEther("1.0")
                })
            ).to.be.revertedWith(
                saleActiveError
            );

            await hhCommunityLaunch.setSaleActive(true);
        });

        it("Should revert when buy with block.number >= startBlock", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).buy({
                    value: ethers.parseEther("1.0")
                })
            ).to.be.revertedWith(
                "CommunityLaunch: Need wait startBlock"
            );
        });

        it("Should buy jav tokens", async () => {
            await helpers.mine(10)

            const buyNativeAmount = ethers.parseEther("1.0");
            const mintedTokens = ethers.parseEther("20")
            const tokenPrice = await hhCommunityLaunch.tokenPrice();
            const amount = buyNativeAmount / tokenPrice;

            await hhCommunityLaunch.connect(addr1).buy(
                {
                    value: buyNativeAmount
                }
            );

            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(amount);
            await expect(await ethers.provider.getBalance(hhCommunityLaunch.target)).to.be.equal(buyNativeAmount);
            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(mintedTokens - amount);
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(mintedTokens - amount);
        });

        it("Should revert when withdraw ADMIN_ERROR", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).withdraw(erc20Token.target, addr1.address, ethers.parseEther("0.0005"))
            ).to.be.revertedWith(
                "CommunityLaunch: only multi sign wallet"
            );
        });

        it("Should revert when withdraw Invalid amount", async () => {
            await expect(
                hhCommunityLaunch.connect(multiSignWallet).withdraw(erc20Token.target, addr1.address, ethers.parseEther("100"))
            ).to.be.revertedWith(
                "CommunityLaunch: Invalid amount"
            );
        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.05")
            const balanceBefore = await erc20Token.balanceOf(addr1.address);

            await hhCommunityLaunch.connect(multiSignWallet).withdraw(erc20Token.target, addr1.address, amount)

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(amount + balanceBefore);
        });
    });
});