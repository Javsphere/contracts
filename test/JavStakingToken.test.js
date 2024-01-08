const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("JavStakingToken contract", () => {
    let hhToken;
    let owner;

    before(async () => {
        const token = await ethers.getContractFactory("JavStakingToken");
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        hhToken = await upgrades.deployProxy(
            token,
            [],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhToken.owner()).to.equal(owner.address);
        });
    });

    describe("Transactions", () => {
        it("Should revert when mint", async () => {
            await expect(
                hhToken.connect(addr1).mint(owner.address, ethers.parseEther("20")),
            ).to.be.revertedWithCustomError(hhToken, "AccessControlUnauthorizedAccount");
        });

        it("Should mint", async () => {
            const amount = ethers.parseEther("20");

            await hhToken.mint(owner.address, amount);

            await expect(await hhToken.totalSupply()).to.equal(amount);
            await expect(await hhToken.balanceOf(owner.address)).to.equal(amount);
        });
    });
});
