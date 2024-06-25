const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR } = require("../common/constanst");
const { deployTokenFixture } = require("../common/mocks");

describe("TokenVestingFreezer contract", () => {
    let hhTokenVesting;
    let owner;
    let addr1;
    let addr2;
    let admin;
    let multiSignWallet;
    let erc20Token;
    let freezerMock;

    async function deployFreezerFixture() {
        const javFreezerFactory = await ethers.getContractFactory("JavFreezer");
        const javFreezer = await upgrades.deployProxy(
            javFreezerFactory,
            [ethers.parseEther("0.05"), 864000, "0x0000000000000000000000000000000000000000"],

            {
                initializer: "initialize",
            },
        );
        await javFreezer.waitForDeployment();
        return javFreezer;
    }

    before(async () => {
        const tokenVesting = await ethers.getContractFactory("TokenVestingFreezer");
        [owner, addr1, addr2, admin, multiSignWallet, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await loadFixture(deployTokenFixture);
        freezerMock = await deployFreezerFixture();

        hhTokenVesting = await upgrades.deployProxy(tokenVesting, [freezerMock.target], {
            initializer: "initialize",
        });
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhTokenVesting.owner()).to.equal(owner.address);
        });

        it("Should set the right freezer address", async () => {
            await expect(await hhTokenVesting.freezer()).to.equal(freezerMock.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhTokenVesting.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhTokenVesting.paused()).to.equal(false);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("20");

            await erc20Token.mint(hhTokenVesting.target, tokenAmounts);
            await expect(await erc20Token.balanceOf(hhTokenVesting.target)).to.equal(tokenAmounts);
        });

        it("Should create freezer pool", async () => {
            const lastRewardBlock = await ethers.provider.getBlockNumber();
            const accRewardPerShare = ethers.parseEther("0.01");

            await freezerMock.addPool(
                erc20Token.target,
                erc20Token.target,
                lastRewardBlock,
                accRewardPerShare,
            );
        });

        it("Should addPoolFee freezer", async () => {
            const fee = {
                depositFee: 1 * 1e4,
                withdrawFee: 1 * 1e4,
                claimFee: 1 * 1e4,
            };

            await freezerMock.addPoolFee(fee);
        });

        it("Should set vesting address", async () => {
            await freezerMock.setVestingAddress(hhTokenVesting.target);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhTokenVesting.connect(addr1).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhTokenVesting.pause();

            await expect(await hhTokenVesting.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhTokenVesting.connect(addr1).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhTokenVesting.unpause();

            await expect(await hhTokenVesting.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhTokenVesting.connect(addr1).setAdminAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhTokenVesting.setAdminAddress(admin.address);

            await expect(await hhTokenVesting.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when setFreezerAddress", async () => {
            await expect(
                hhTokenVesting.connect(addr1).setFreezerAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setFreezerAddress", async () => {
            await hhTokenVesting.setFreezerAddress(freezerMock.target);

            await expect(await hhTokenVesting.freezer()).to.equal(freezerMock.target);
        });

        it("Should revert when addAllowedAddress", async () => {
            await expect(
                hhTokenVesting.connect(addr1).addAllowedAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addAllowedAddress", async () => {
            await hhTokenVesting.addAllowedAddress(admin.address);

            const allowedAddresses = await hhTokenVesting.getAllowedAddresses();

            await expect(allowedAddresses[1]).to.be.equal(admin.address);
        });

        it("Should revert when removeAllowedAddress", async () => {
            await expect(
                hhTokenVesting.connect(addr1).removeAllowedAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should removeAllowedAddress", async () => {
            await hhTokenVesting.addAllowedAddress(addr1.address);
            await hhTokenVesting.removeAllowedAddress(addr1.address);
        });

        it("Should revert when create vesting schedule batch - not allowed address", async () => {
            const vestingInfo = [
                {
                    beneficiary: "0x0000000000000000000000000000000000000000",
                    start: 1,
                    cliff: 1,
                    duration: 1,
                    slicePeriodSeconds: 1,
                    revocable: true,
                    amount: 1,
                    vestingType: 1,
                    lockId: 0,
                },
            ];
            await expect(
                hhTokenVesting.connect(addr1).createVestingScheduleBatch(vestingInfo),
            ).to.be.revertedWith("TokenVesting: only allowed addresses");
        });

        it("Should revert when create vesting schedule - not allowed address", async () => {
            await expect(
                hhTokenVesting
                    .connect(addr1)
                    .createVestingSchedule(
                        "0x0000000000000000000000000000000000000000",
                        1,
                        1,
                        1,
                        1,
                        true,
                        1,
                        0,
                        0,
                    ),
            ).to.be.revertedWith("TokenVesting: only allowed addresses");
        });

        it("Should revert when create vesting schedule - duration <= 0", async () => {
            const vestingInfo = [
                {
                    beneficiary: "0x0000000000000000000000000000000000000000",
                    start: 1,
                    cliff: 1,
                    duration: 0,
                    slicePeriodSeconds: 1,
                    revocable: true,
                    amount: 1,
                    vestingType: 1,
                    lockId: 0,
                },
            ];
            await expect(
                hhTokenVesting.connect(admin).createVestingScheduleBatch(vestingInfo),
            ).to.be.revertedWith("TokenVesting: duration must be > 0");
        });

        it("Should revert when create vesting schedule - amount <= 0", async () => {
            const vestingInfo = [
                {
                    beneficiary: "0x0000000000000000000000000000000000000000",
                    start: 1,
                    cliff: 1,
                    duration: 1,
                    slicePeriodSeconds: 1,
                    revocable: true,
                    amount: 0,
                    vestingType: 0,
                    lockId: 0,
                },
            ];
            await expect(
                hhTokenVesting.connect(admin).createVestingScheduleBatch(vestingInfo),
            ).to.be.revertedWith("TokenVesting: amount must be > 0");
        });

        it("Should revert when create vesting schedule - slicePeriodSeconds <= 0", async () => {
            const vestingInfo = [
                {
                    beneficiary: "0x0000000000000000000000000000000000000000",
                    start: 1,
                    cliff: 1,
                    duration: 1,
                    slicePeriodSeconds: 0,
                    revocable: true,
                    amount: 1,
                    vestingType: 1,
                    lockId: 0,
                },
            ];
            await expect(
                hhTokenVesting.connect(admin).createVestingScheduleBatch(vestingInfo),
            ).to.be.revertedWith("TokenVesting: slicePeriodSeconds must be > 0");
        });

        it("Should revert when create vesting schedule - duration < cliff", async () => {
            const vestingInfo = [
                {
                    beneficiary: "0x0000000000000000000000000000000000000000",
                    start: 1,
                    cliff: 2,
                    duration: 1,
                    slicePeriodSeconds: 1,
                    revocable: true,
                    amount: 1,
                    vestingType: 1,
                    lockId: 0,
                },
            ];
            await expect(
                hhTokenVesting.connect(admin).createVestingScheduleBatch(vestingInfo),
            ).to.be.revertedWith("TokenVesting: duration must be >= cliff");
        });

        it("Should create vesting schedule batch", async () => {
            const beneficiary = addr1.address;
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("0.0005");

            const currentVestingId = await hhTokenVesting.currentVestingId();
            const vestingInfo = [
                {
                    beneficiary: beneficiary,
                    start: start,
                    cliff: cliff,
                    duration: duration,
                    slicePeriodSeconds: slicePeriodSeconds,
                    revocable: revocable,
                    amount: amount,
                    vestingType: 1,
                    lockId: 0,
                },
            ];

            await hhTokenVesting.createVestingScheduleBatch(vestingInfo);

            const vestingScheduleForHolder = await hhTokenVesting.getLastVestingScheduleForHolder(
                beneficiary,
            );

            await expect(await hhTokenVesting.currentVestingId()).to.be.equal(
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
            await expect(vestingScheduleForHolder.vestingType).to.be.equal(1);
        });

        it("Should create vesting schedule", async () => {
            const beneficiary = addr1.address;
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("0.0005");

            const currentVestingId = await hhTokenVesting.currentVestingId();

            await hhTokenVesting.createVestingSchedule(
                beneficiary,
                start,
                cliff,
                duration,
                slicePeriodSeconds,
                revocable,
                amount,
                1,
                0,
            );

            const vestingScheduleForHolder = await hhTokenVesting.getLastVestingScheduleForHolder(
                beneficiary,
            );

            await expect(await hhTokenVesting.currentVestingId()).to.be.equal(
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
            await expect(vestingScheduleForHolder.vestingType).to.be.equal(1);
        });

        it("Should revert when revoke", async () => {
            await expect(
                hhTokenVesting
                    .connect(addr1)
                    .revoke("0xd283f3979d00cb5493f2da07819695bc299fba34aa6e0bacb484fe07a2fc0ae0"),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when revoke - vesting is not revocable", async () => {
            const beneficiary = addr1.address;
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = false;
            const amount = ethers.parseEther("0.0005");

            const currentVestingId = await hhTokenVesting.currentVestingId();
            const vestingInfo = [
                {
                    beneficiary: beneficiary,
                    start: start,
                    cliff: cliff,
                    duration: duration,
                    slicePeriodSeconds: slicePeriodSeconds,
                    revocable: revocable,
                    amount: amount,
                    vestingType: 1,
                    lockId: 0,
                },
            ];

            await hhTokenVesting.createVestingScheduleBatch(vestingInfo);
            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );

            await expect(hhTokenVesting.connect(admin).revoke(scheduleId)).to.be.revertedWith(
                "TokenVesting: vesting is not revocable",
            );
        });

        it("Should revoke", async () => {
            const beneficiary = addr2.address;
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("0.0005");

            await erc20Token.mint(freezerMock.target, ethers.parseEther("1"));

            const vestingInfo = [
                {
                    beneficiary: beneficiary,
                    start: start,
                    cliff: cliff,
                    duration: duration,
                    slicePeriodSeconds: slicePeriodSeconds,
                    revocable: revocable,
                    amount: amount,
                    vestingType: 1,
                    lockId: 0,
                },
            ];

            await hhTokenVesting.createVestingScheduleBatch(vestingInfo);

            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );

            await hhTokenVesting.revoke(scheduleId);

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(
                beneficiary,
                index,
            );

            await expect(vestingSchedule.revoked).to.be.equal(true);
        });

        it("Should revert when revoke - already revoked", async () => {
            const beneficiary = addr2.address;
            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );

            await expect(hhTokenVesting.connect(admin).revoke(scheduleId)).to.be.reverted;
        });

        it("Should revoke when release - not contract owner", async () => {
            const beneficiary = addr1.address;
            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );

            await expect(hhTokenVesting.connect(addr2).release(scheduleId)).to.be.revertedWith(
                "TokenVesting: only beneficiary and owner can release vested tokens",
            );
        });

        it("Should revoke when release - not contract beneficiary", async () => {
            const beneficiary = addr1.address;
            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );

            await expect(hhTokenVesting.connect(addr2).release(scheduleId)).to.be.revertedWith(
                "TokenVesting: only beneficiary and owner can release vested tokens",
            );
        });

        it("Should release", async () => {
            const beneficiary = addr1.address;
            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );
            const releaseAmount = await hhTokenVesting.computeReleasableAmount(scheduleId);
            const depositId = await hhTokenVesting.vestingFreezeId(scheduleId);
            const userDepositBefore = await freezerMock.userDeposits(beneficiary, 0, depositId);

            await hhTokenVesting.connect(addr1).release(scheduleId);
            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(
                beneficiary,
                index,
            );
            const userDeposit = await freezerMock.userDeposits(beneficiary, 0, depositId);

            await expect(vestingSchedule.released).to.be.equal(releaseAmount);
            const claimAmount = userDeposit[4] - userDepositBefore[4];

            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                releaseAmount + claimAmount,
            );
        });

        it("Should revoke when release - vestedAmount = 0 ", async () => {
            const beneficiary = addr1.address;
            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );

            await expect(hhTokenVesting.connect(addr1).release(scheduleId)).to.be.revertedWith(
                "TokenVesting: invalid releasable amount",
            );
        });

        it("Should compute vesting schedule id for address and index", async () => {
            const scheduleId = "0x3f68e79174daf15b50e15833babc8eb7743e730bb9606f922c48e95314c3905c";

            await expect(
                await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(addr1.address, 1),
            ).to.be.equal(scheduleId);
        });

        it("Should compute releasable amount when currentTime < vestingSchedule.cliff", async () => {
            const beneficiary = addr2.address;

            const start = await time.latest();
            const cliff = 120;
            const duration = 200;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("0.0005");

            const vestingInfo = [
                {
                    beneficiary: beneficiary,
                    start: start,
                    cliff: cliff,
                    duration: duration,
                    slicePeriodSeconds: slicePeriodSeconds,
                    revocable: revocable,
                    amount: amount,
                    vestingType: 1,
                    lockId: 0,
                },
            ];

            await hhTokenVesting.createVestingScheduleBatch(vestingInfo);

            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );
            const currentTime = await time.latest();

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(
                beneficiary,
                index,
            );

            const releasableAmount = 0;

            await expect(vestingSchedule.cliff).to.be.above(currentTime);
            await expect(await hhTokenVesting.computeReleasableAmount(scheduleId)).to.be.equal(
                releasableAmount,
            );
        });

        it("Should compute releasable amount when currentTime >= duration", async () => {
            const beneficiary = addr2.address;

            const start = await time.latest();
            const cliff = 0;
            const duration = 1;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("0.0005");

            const vestingInfo = [
                {
                    beneficiary: beneficiary,
                    start: start,
                    cliff: cliff,
                    duration: duration,
                    slicePeriodSeconds: slicePeriodSeconds,
                    revocable: revocable,
                    amount: amount,
                    vestingType: 1,
                    lockId: 0,
                },
            ];

            await hhTokenVesting.createVestingScheduleBatch(vestingInfo);

            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );
            const currentTime = await time.latest();

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(
                beneficiary,
                index,
            );

            const releasableAmount = vestingSchedule.amountTotal - vestingSchedule.released;

            await expect(vestingSchedule.start + vestingSchedule.duration).to.be.least(currentTime);
            await expect(await hhTokenVesting.computeReleasableAmount(scheduleId)).to.be.equal(
                releasableAmount,
            );
        });

        it("Should compute releasable amount when currentTime < duration", async () => {
            const beneficiary = addr2.address;

            const start = await time.latest();
            const cliff = 0;
            const duration = 1111;
            const slicePeriodSeconds = 2;
            const amount = ethers.parseEther("0.0005");

            const vestingInfo = [
                {
                    beneficiary: beneficiary,
                    start: start,
                    cliff: cliff,
                    duration: duration,
                    slicePeriodSeconds: slicePeriodSeconds,
                    revocable: true,
                    amount: amount,
                    vestingType: 1,
                    lockId: 0,
                },
            ];

            await hhTokenVesting.createVestingScheduleBatch(vestingInfo);

            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);
            const scheduleId = await hhTokenVesting.computeVestingScheduleIdForAddressAndIndex(
                beneficiary,
                index,
            );
            const currentTime = await time.latest();

            const vestingSchedule = await hhTokenVesting.getVestingScheduleByAddressAndIndex(
                beneficiary,
                index,
            );
            const timeFromStart = BigInt(currentTime) - vestingSchedule.start;
            const secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            const vestedSlicePeriods = timeFromStart / secondsPerSlice;
            const vestedSeconds = vestedSlicePeriods * secondsPerSlice;

            const releasableAmount =
                (vestingSchedule.amountTotal * vestedSeconds) / vestingSchedule.duration;

            await expect(vestingSchedule.start + vestingSchedule.duration).to.be.above(currentTime);
            await expect(await hhTokenVesting.computeReleasableAmount(scheduleId)).to.be.equal(
                releasableAmount,
            );
        });

        it("Should get last vesting schedule for holder", async () => {
            const beneficiary = addr1.address;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const amount = ethers.parseEther("0.0005");

            const vestingScheduleForHolder = await hhTokenVesting.getLastVestingScheduleForHolder(
                beneficiary,
            );

            await expect(vestingScheduleForHolder.initialized).to.be.equal(true);
            await expect(vestingScheduleForHolder.beneficiary).to.be.equal(beneficiary);
            await expect(vestingScheduleForHolder.duration).to.be.equal(duration);
            await expect(vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                slicePeriodSeconds,
            );
            await expect(vestingScheduleForHolder.revocable).to.be.equal(false);
            await expect(vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(vestingScheduleForHolder.released).to.be.equal(amount);
            await expect(vestingScheduleForHolder.revoked).to.be.equal(false);
        });

        it("Should get vesting schedule by address and index", async () => {
            const beneficiary = addr1.address;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const amount = ethers.parseEther("0.0005");

            const index = (await hhTokenVesting.holdersVestingCount(beneficiary)) - BigInt(1);

            const vestingScheduleForHolder =
                await hhTokenVesting.getVestingScheduleByAddressAndIndex(beneficiary, index);

            await expect(vestingScheduleForHolder.initialized).to.be.equal(true);
            await expect(vestingScheduleForHolder.beneficiary).to.be.equal(beneficiary);
            await expect(vestingScheduleForHolder.duration).to.be.equal(duration);
            await expect(vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                slicePeriodSeconds,
            );
            await expect(vestingScheduleForHolder.revocable).to.be.equal(false);
            await expect(vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(vestingScheduleForHolder.released).to.be.equal(amount);
            await expect(vestingScheduleForHolder.revoked).to.be.equal(false);
        });
    });
});
