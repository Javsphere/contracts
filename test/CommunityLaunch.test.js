const {expect} = require("chai");
const {ethers} = require("hardhat")
const {
    loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");


describe("CommunityLaunch contract", () => {
    let hhCommunityLaunch;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let mockedJavToken;
    let adminError;
    let saleActiveError;
    let javPrice;

    async function deployTokenFixture() {
        const javToken = await ethers.deployContract("JavlisToken");
        await javToken.initialize();
        return javToken
    }

    before(async () => {
        const communityLaunch = await ethers.getContractFactory("CommunityLaunch");
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        admin = addrs[4];
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        mockedJavToken = await loadFixture(deployTokenFixture);
        javPrice = ethers.parseEther("0.02")

        hhCommunityLaunch = await communityLaunch.deploy();
        await hhCommunityLaunch.initialize(
            mockedJavToken.target,
            javPrice
        );

        adminError = "CommunityLaunch: only admin"
        saleActiveError = "CommunityLaunch: contract is not available right now"

    });

    describe("Deployment", () => {

        it("Should set the right owner address", async () => {

            await expect(await hhCommunityLaunch.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {

            await expect(await hhCommunityLaunch.token()).to.equal(mockedJavToken.target);
        });

        it("Should set the right admin address", async () => {

            await expect(await hhCommunityLaunch.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right isSaleActive flag", async () => {

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(false);
        });

        it("Should set the right javPrice", async () => {

            await expect(await hhCommunityLaunch.javPrice()).to.equal(javPrice);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("20")

            await mockedJavToken.mint(hhCommunityLaunch.target, tokenAmounts);
            await expect(await mockedJavToken.balanceOf(hhCommunityLaunch.target)).to.equal(tokenAmounts);
        });


    });

    describe("Transactions", () => {
        it("Should revert when set the admin address", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setAdminAddress(admin.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the admin address", async () => {
            await hhCommunityLaunch.setAdminAddress(admin.address);

            await expect(await hhCommunityLaunch.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when set setSaleActive", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setSaleActive(true)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the setSaleActive", async () => {
            await hhCommunityLaunch.setSaleActive(true);

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(true);
        });

        it("Should revert when set the setJavPrice", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setJavPrice(ethers.parseEther("0.0005"))
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the setJavPrice", async () => {
            javPrice = ethers.parseEther("0.05")
            await hhCommunityLaunch.setJavPrice(javPrice);

            await expect(await hhCommunityLaunch.javPrice()).to.equal(javPrice);
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

        it("Should buy jav tokens", async () => {
            const buyNativeAmount = ethers.parseEther("1.0");
            const mintedTokens = ethers.parseEther("20")
            const tokenPrice = await hhCommunityLaunch.javPrice();
            const amount = buyNativeAmount / tokenPrice;

            await hhCommunityLaunch.connect(addr1).buy(
                {
                    value: buyNativeAmount
                }
            );

            await expect(await mockedJavToken.balanceOf(addr1.address)).to.be.equal(amount);
            await expect(await ethers.provider.getBalance(hhCommunityLaunch.target)).to.be.equal(buyNativeAmount);
            await expect(await mockedJavToken.balanceOf(hhCommunityLaunch.target)).to.be.equal(mintedTokens - amount);
        });

        it("Should revert when withdraw", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).withdraw(mockedJavToken.target, ethers.parseEther("0.0005"))
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.05")

            await hhCommunityLaunch.withdraw(mockedJavToken.target, amount)

            await expect(await mockedJavToken.balanceOf(owner.address)).to.equal(amount);
        });
    });
});