const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR } = require("../common/constanst");
const { deployTokenFixture } = require("../common/mocks");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Airdrop contract", () => {
    let hhAirdrop;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let vestingMock;

    async function deployVestingFixture() {
        const tokenVestingFactory = await ethers.getContractFactory("TokenVestingFreezer");
        const freezerContractFactory = await ethers.getContractFactory("JavFreezerMock");
        const erc20Token = await loadFixture(deployTokenFixture);
        const freezer = await freezerContractFactory.deploy();
        await freezer.waitForDeployment();

        const hhTokenVesting = await upgrades.deployProxy(tokenVestingFactory, [freezer.target], {
            initializer: "initialize",
        });

        await hhTokenVesting.waitForDeployment();
        await erc20Token.mint(hhTokenVesting.target, ethers.parseEther("20"));
        return hhTokenVesting;
    }

    before(async () => {
        const airdrop = await ethers.getContractFactory("Airdrop");
        [owner, addr1, addr2, admin, multiSignWallet, ...addrs] = await ethers.getSigners();
        vestingMock = await helpers.loadFixture(deployVestingFixture);

        hhAirdrop = await upgrades.deployProxy(airdrop, [vestingMock.target], {
            initializer: "initialize",
        });
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhAirdrop.owner()).to.equal(owner.address);
        });

        it("Should set the right vesting address", async () => {
            await expect(await hhAirdrop.vestingAddress()).to.equal(vestingMock.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhAirdrop.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhAirdrop.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhAirdrop.connect(addr1).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhAirdrop.pause();

            await expect(await hhAirdrop.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhAirdrop.connect(addr1).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhAirdrop.unpause();

            await expect(await hhAirdrop.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhAirdrop.connect(addr1).setAdminAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhAirdrop.setAdminAddress(admin.address);

            await expect(await hhAirdrop.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when set the vesting address", async () => {
            await expect(
                hhAirdrop.connect(addr1).setVestingAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the vesting address", async () => {
            await hhAirdrop.setVestingAddress(vestingMock.target);

            await expect(await hhAirdrop.vestingAddress()).to.equal(vestingMock.target);
        });

        it("Should revert when dropVestingTokens - not admin", async () => {
            const recipients = ["0x0000000000000000000000000000000000000000"];

            await expect(
                hhAirdrop.connect(addr1).dropVestingTokens(recipients, 1, 1, 1, 1, true, 1, 1, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should drop vesting tokens", async () => {
            const beneficiary = addr1.address;
            const recipients = [beneficiary];
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("0.0005");
            const vestingType = 5;

            await vestingMock.addAllowedAddress(hhAirdrop.target);

            const currentVestingId = await vestingMock.currentVestingId();

            await hhAirdrop.dropVestingTokens(
                recipients,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                revocable,
                amount,
                vestingType,
                1,
            );

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                beneficiary,
            );

            await expect(await vestingMock.currentVestingId()).to.be.equal(
                currentVestingId + BigInt(1),
            );
            await expect(vestingScheduleForHolder.initialized).to.be.equal(true);
            await expect(vestingScheduleForHolder.beneficiary).to.be.equal(beneficiary);
            await expect(vestingScheduleForHolder.cliff).to.be.equal(cliff + start);
            await expect(vestingScheduleForHolder.duration).to.be.equal(duration);
            await expect(vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                slicePeriodSeconds,
            );
            await expect(vestingScheduleForHolder.revocable).to.be.equal(revocable);
            await expect(vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(vestingScheduleForHolder.released).to.be.equal(0);
            await expect(vestingScheduleForHolder.revoked).to.be.equal(false);
            await expect(vestingScheduleForHolder.vestingType).to.be.equal(vestingType);
        });
    });
});
