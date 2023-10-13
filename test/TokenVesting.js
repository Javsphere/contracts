const {expect} = require("chai");
const {ethers} = require("hardhat")
const {
    loadFixture,
    time
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");


describe("TokenVesting contract", () => {
    let hhTokenVesting;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let mockedJavToken;
    let adminError;

    async function deployTokenFixture() {
        const javToken = await ethers.deployContract("JavlisToken");
        await javToken.initialize();
        return javToken
    }

    before(async () => {
        const tokenVesting = await ethers.getContractFactory("TokenVesting");
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        admin = addrs[4];
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        mockedJavToken = await loadFixture(deployTokenFixture);

        hhTokenVesting = await tokenVesting.deploy();
        await hhTokenVesting.initialize(
            mockedJavToken.target
        );

        adminError = "TokenVesting: only admin"

    });

    describe("Deployment", () => {

        it("Should set the right owner address", async () => {

            await expect(await hhTokenVesting.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {

            await expect(await hhTokenVesting.token()).to.equal(mockedJavToken.target);
        });

        it("Should set the right admin address", async () => {

            await expect(await hhTokenVesting.adminAddress()).to.equal(owner.address);
        });

         it("Should set the _paused status", async () => {

            await expect(await hhTokenVesting.paused()).to.equal(false);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("20")

            await mockedJavToken.mint(hhTokenVesting.target, tokenAmounts);
            await expect(await mockedJavToken.balanceOf(hhTokenVesting.target)).to.equal(tokenAmounts);
        });


    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(
                hhTokenVesting.connect(addr1).pause()
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set pause", async () => {
            await hhTokenVesting.pause();

            await expect(await hhTokenVesting.paused()).to.equal(true);
        });

         it("Should revert when set unpause", async () => {
            await expect(
                hhTokenVesting.connect(addr1).unpause()
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set unpause", async () => {
            await hhTokenVesting.unpause();

            await expect(await hhTokenVesting.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhTokenVesting.connect(addr1).setAdminAddress(admin.address)
            ).to.be.revertedWith(
                adminError
            );

        });

        it("Should set the admin address", async () => {
            await hhTokenVesting.setAdminAddress(admin.address);

            await expect(await hhTokenVesting.adminAddress()).to.equal(admin.address);
        });


        it("Should revert when revoke", async () => {
            await expect(
                hhTokenVesting.connect(addr1).createVestingSchedule(
                    "0x0000000000000000000000000000000000000000",
                    1,
                    1,
                    1,
                    1,
                    true,
                    1,
                )
            ).to.be.revertedWith(adminError);

        });

        it("Should create vesting schedule", async () => {
            const beneficiary = addr1.address
            const start = await time.latest();
            const cliff = 2
            const duration = 3
            const slicePeriodSeconds = 1
            const revocable = true
            const amount = ethers.parseEther("0.0005")

            const currentVestingId = await hhTokenVesting.currentVestingId()

            await hhTokenVesting.createVestingSchedule(
                beneficiary,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                revocable,
                amount
            );

            const vestingScheduleForHolder = await hhTokenVesting.getLastVestingScheduleForHolder(beneficiary);

            await expect(await hhTokenVesting.currentVestingId()).to.be.equal(currentVestingId + BigInt(1));
            await expect(vestingScheduleForHolder.initialized).to.be.equal(true);
            await expect(vestingScheduleForHolder.beneficiary).to.be.equal(beneficiary);
            await expect(vestingScheduleForHolder.cliff).to.be.equal(cliff + start);
            await expect(vestingScheduleForHolder.duration).to.be.equal(duration);
            await expect(vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(slicePeriodSeconds);
            await expect(vestingScheduleForHolder.revocable).to.be.equal(revocable);
            await expect(vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(vestingScheduleForHolder.released).to.be.equal(0);
            await expect(vestingScheduleForHolder.revoked).to.be.equal(false);

        });

        it("Should revert when revoke", async () => {
            await expect(
                hhTokenVesting.connect(addr1).revoke(
                    "0xd283f3979d00cb5493f2da07819695bc299fba34aa6e0bacb484fe07a2fc0ae0"
                )).to.be.revertedWith(adminError);

        });

        it("Should revoke", async () => {
            const beneficiary = addr2.address;
            const start = await time.latest();
            const cliff = 2
            const duration = 3
            const slicePeriodSeconds = 1
            const revocable = true
            const amount = ethers.parseEther("0.0005")

            await hhTokenVesting.createVestingSchedule(
                beneficiary,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                revocable,
                amount
            );

            const index = await hhTokenVesting.holdersVestingCount(beneficiary) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(beneficiary, index);

            await hhTokenVesting.revoke(scheduleId);

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);

            await expect(vestingSchedule.revoked).to.be.equal(true);
        });

        it("Should revert when withdraw", async () => {
            await expect(
                hhTokenVesting.connect(addr1).withdraw(1)
            ).to.be.revertedWith(adminError);

        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.0005")

            await hhTokenVesting.withdraw(amount);

            await expect(await mockedJavToken.balanceOf(owner.address)).to.be.equal(amount);
        });

        it("Should release", async () => {
            const beneficiary = addr1.address
            const releaseAmount = ethers.parseEther("0.0005")
            const index = await hhTokenVesting.holdersVestingCount(beneficiary) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(beneficiary, index);

            await hhTokenVesting.connect(addr1).release(scheduleId, releaseAmount);
            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);

            await expect(vestingSchedule.released).to.be.equal(releaseAmount);
            await expect(await mockedJavToken.balanceOf(addr1.address)).to.be.equal(releaseAmount);
        });

        it("Should compute vesting schedule id for address and index", async () => {
            const scheduleId = "0x3f68e79174daf15b50e15833babc8eb7743e730bb9606f922c48e95314c3905c"

            await expect(await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(addr1.address, 1)).to.be.equal(scheduleId)
        });

        it("Should compute releasable amount when currentTime < vestingSchedule.cliff", async () => {
            const beneficiary = addr2.address

            const start = await time.latest();
            const cliff = 120
            const duration = 200
            const slicePeriodSeconds = 1
            const revocable = true
            const amount = ethers.parseEther("0.0005")

            await hhTokenVesting.createVestingSchedule(
                beneficiary,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                revocable,
                amount
            );

            const index = await hhTokenVesting.holdersVestingCount(beneficiary) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(beneficiary, index)
            const currentTime = await time.latest();

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);

            const releasableAmount = 0;

            await expect(vestingSchedule.cliff).to.be.above(currentTime)
            await expect(await hhTokenVesting.computeReleasableAmount(scheduleId)).to.be.equal(releasableAmount);

        });


        it("Should compute releasable amount when currentTime >= duration", async () => {
            const beneficiary = addr2.address

            const start = await time.latest();
            const cliff = 0
            const duration = 1
            const slicePeriodSeconds = 1
            const revocable = true
            const amount = ethers.parseEther("0.0005")

            await hhTokenVesting.createVestingSchedule(
                beneficiary,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                revocable,
                amount
            );

            const index = await hhTokenVesting.holdersVestingCount(beneficiary) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(beneficiary, index)
            const currentTime = await time.latest();

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);

            const releasableAmount = vestingSchedule.amountTotal - vestingSchedule.released;

            await expect(vestingSchedule.start + vestingSchedule.duration).to.be.least(currentTime)
            await expect(await hhTokenVesting.computeReleasableAmount(scheduleId)).to.be.equal(releasableAmount);

        });

        it("Should compute releasable amount when currentTime < duration", async () => {
            const beneficiary = addr2.address

            const start = await time.latest();
            const cliff = 0
            const duration = 1111
            const slicePeriodSeconds = 2
            const amount = ethers.parseEther("0.0005")

            await hhTokenVesting.createVestingSchedule(
                beneficiary,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                true,
                amount
            );

            const index = await hhTokenVesting.holdersVestingCount(beneficiary) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(beneficiary, index)
            const currentTime = await time.latest();

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);
            const timeFromStart = BigInt(currentTime) - vestingSchedule.start
            const secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            const vestedSlicePeriods = timeFromStart / secondsPerSlice;
            const vestedSeconds = vestedSlicePeriods * secondsPerSlice;

            const releasableAmount = (vestingSchedule.amountTotal * vestedSeconds) / vestingSchedule.duration

            await expect(vestingSchedule.start + vestingSchedule.duration).to.be.above(currentTime)
            await expect(await hhTokenVesting.computeReleasableAmount(scheduleId)).to.be.equal(releasableAmount);

        });

        it("Should get last vesting schedule for holder", async () => {
            const beneficiary = addr1.address
            const duration = 3
            const slicePeriodSeconds = 1
            const revocable = true
            const amount = ethers.parseEther("0.0005")

            const vestingScheduleForHolder = await hhTokenVesting.getLastVestingScheduleForHolder(beneficiary);

            await expect(vestingScheduleForHolder.initialized).to.be.equal(true);
            await expect(vestingScheduleForHolder.beneficiary).to.be.equal(beneficiary);
            await expect(vestingScheduleForHolder.duration).to.be.equal(duration);
            await expect(vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(slicePeriodSeconds);
            await expect(vestingScheduleForHolder.revocable).to.be.equal(revocable);
            await expect(vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(vestingScheduleForHolder.released).to.be.equal(amount);
            await expect(vestingScheduleForHolder.revoked).to.be.equal(false);

        });

        it("Should revert when get withdrawable amount", async () => {
            await expect(
                hhTokenVesting.connect(addr1).getWithdrawableAmount()
            ).to.be.revertedWith(adminError);

        });

        it("Should get right withdrawable amount", async () => {
            const vestingSchedulesTotalAmount = await hhTokenVesting.vestingSchedulesTotalAmount()
            const totalAmount = await mockedJavToken.balanceOf(hhTokenVesting.target)

            await expect(await hhTokenVesting.getWithdrawableAmount()).to.be.equal(totalAmount - vestingSchedulesTotalAmount);

        });

        it("Should get vesting schedule by address and index", async () => {
            const beneficiary = addr1.address
            const duration = 3
            const slicePeriodSeconds = 1
            const revocable = true
            const amount = ethers.parseEther("0.0005")

            const index = await hhTokenVesting.holdersVestingCount(beneficiary) - BigInt(1);

            const vestingScheduleForHolder = await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);

            await expect(vestingScheduleForHolder.initialized).to.be.equal(true);
            await expect(vestingScheduleForHolder.beneficiary).to.be.equal(beneficiary);
            await expect(vestingScheduleForHolder.duration).to.be.equal(duration);
            await expect(vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(slicePeriodSeconds);
            await expect(vestingScheduleForHolder.revocable).to.be.equal(revocable);
            await expect(vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(vestingScheduleForHolder.released).to.be.equal(amount);
            await expect(vestingScheduleForHolder.revoked).to.be.equal(false);

        });
    });
});


