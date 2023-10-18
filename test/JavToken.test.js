const {expect} = require("chai");
const {ethers} = require("hardhat");


describe("JavlisToken contract", () => {
    let hhToken;
    let owner;

    before(async () => {
        const token = await ethers.getContractFactory("JavlisToken");
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;

        hhToken = await token.deploy();
        await hhToken.initialize();


    });

    describe("Deployment", () => {

        it("Should set the right owner address", async () => {

            await expect(await hhToken.owner()).to.equal(owner.address);
        });


    });
});


