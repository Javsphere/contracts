const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("JavToken contract", () => {
    let hhToken;
    let owner;

    before(async () => {
        const token = await ethers.getContractFactory("JavToken");
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        hhToken = await upgrades.deployProxy(
            token,
            [ethers.parseEther("1000")],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhToken.owner()).to.equal(owner.address);
        });

        it("Should set the right cap", async () => {
            await expect(await hhToken.cap()).to.equal(ethers.parseEther("1000"));
        });
    });

    describe("Transactions", () => {
        it("Should revert when mint", async () => {
            await expect(
                hhToken.connect(addr1).mint(owner.address, ethers.parseEther("20")),
            ).to.be.revertedWithCustomError(hhToken, "OwnableUnauthorizedAccount");
        });

        it("Should mint", async () => {
            const amount = ethers.parseEther("20");

            await hhToken.mint(owner.address, amount);

            await expect(await hhToken.totalSupply()).to.equal(amount);
            await expect(await hhToken.balanceOf(owner.address)).to.equal(amount);
        });

        it("Should burn", async () => {
            const amount = ethers.parseEther("10");

            await hhToken.connect(owner).burn(amount);

            await expect(await hhToken.totalSupply()).to.equal(amount);
            await expect(await hhToken.balanceOf(owner.address)).to.equal(amount);
        });
    });
});
