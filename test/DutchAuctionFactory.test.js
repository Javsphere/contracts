const {expect} = require("chai");
const {ethers, upgrades} = require("hardhat")
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {address} = require("hardhat/internal/core/config/config-validation");


describe("DutchAuctionFactory contract", () => {
    let hhDAuctionF;
    let owner;
    let addr1;
    let tokenAddress;
    let admin;
    let signer1;
    let signer2;
    let signer3;
    let adminError;


    before(async () => {
        const dutchAuctionFactory = await ethers.getContractFactory("DutchAuctionFactory");
        [owner, addr1, admin, signer1, signer2, signer3, ...addrs] = await ethers.getSigners();
        tokenAddress = ethers.Wallet.createRandom().address;

        hhDAuctionF = await upgrades.deployProxy(
            dutchAuctionFactory,
            [
                tokenAddress,
                2,
                [signer1.address, signer2.address, signer3.address]
            ],

            {
                initializer: "initialize",
            }
        );

        adminError = "DutchAuctionFactory: only admin"

    });

    describe("Deployment", () => {

        it("Should set the right owner address", async () => {

            await expect(await hhDAuctionF.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {

            await expect(await hhDAuctionF.tokenAddress()).to.equal(tokenAddress);
        });

        it("Should set the right admin address", async () => {

            await expect(await hhDAuctionF.adminAddress()).to.equal(owner.address);
        });


    });

    describe("Transactions", () => {
        it("Should revert when set the admin address", async () => {
            await expect(
                hhDAuctionF.connect(addr1).setAdminAddress(admin.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the admin address", async () => {
            await hhDAuctionF.setAdminAddress(admin.address);

            await expect(await hhDAuctionF.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when set the token address", async () => {
            await expect(
                hhDAuctionF.connect(addr1).setTokenAddress(admin.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the token address", async () => {
            await hhDAuctionF.setTokenAddress(tokenAddress);

            await expect(await hhDAuctionF.tokenAddress()).to.equal(tokenAddress);
        });

        it("Should revert deploy admin error", async () => {
            await expect(
                hhDAuctionF.connect(addr1).deploy(1,2,3,4)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should revert when deploy multisign error", async () => {
            await expect(
                hhDAuctionF.deploy(1,2,3,4)
            ).to.be.revertedWith(
                "MultiSignatureUpgradeable: need more signatures"
            );

        });

        it("Should deploy", async () => {
            const action = await hhDAuctionF.DEPLOY();

            hhDAuctionF.connect(signer1).signAction(action);
            hhDAuctionF.connect(signer2).signAction(action);

            await helpers.mine(1);

            await hhDAuctionF.deploy(1,2,4,1);

            await expect((await hhDAuctionF.getAuctions()).length).to.equal(1);
        });
        
        it("Should get right auctions", async () => {
            const auctions = await hhDAuctionF.getAuctions();

            await expect(auctions.length).to.equal(1);
        });

        it("Should deploy one more auction", async () => {
            const action = await hhDAuctionF.DEPLOY();

            hhDAuctionF.connect(signer1).signAction(action);
            hhDAuctionF.connect(signer2).signAction(action);

            await helpers.mine(1);

            await hhDAuctionF.deploy(1,2,4,1);

            await expect((await hhDAuctionF.getAuctions()).length).to.equal(2);
        });

        it("Should get right auctionAt", async () => {
            const auctions = await hhDAuctionF.getAuctions();

            await expect(await hhDAuctionF.getAuctionAt(0)).to.equal(auctions[0]);
            await expect(await hhDAuctionF.getAuctionAt(1)).to.equal(auctions[1]);
        });
        
    });
});