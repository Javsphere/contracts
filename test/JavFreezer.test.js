const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR, MANAGER_ERROR } = require("./common/constanst");
const { deployTokenFixture, deployInfinityPassFixture } = require("./common/mocks");
const { time, mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("JavFreezer contract", () => {
    let hhJavFreezer;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let vesting;
    let rewardsDistributor;
    let erc20Token;
    let infinityPass;

    before(async () => {
        const javFreezer = await ethers.getContractFactory("JavFreezer");
        [owner, addr1, addr2, addr3, bot, vesting, rewardsDistributor, ...addrs] =
            await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        infinityPass = await helpers.loadFixture(deployInfinityPassFixture);
        const rewardPerBlock = ethers.parseEther("0.05");
        const rewardUpdateBlocksInterval = 864000;
        const infinityPassPercent = 5;

        hhJavFreezer = await upgrades.deployProxy(
            javFreezer,
            [
                rewardPerBlock,
                rewardUpdateBlocksInterval,
                vesting.address,
                infinityPassPercent,
                infinityPass.target,
                nonZeroAddress,
            ],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavFreezer.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavFreezer.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right vesting address", async () => {
            await expect(await hhJavFreezer.vestingAddress()).to.equal(vesting.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavFreezer.paused()).to.equal(false);
        });

        it("Should set the right rewardPerBlock", async () => {
            await expect(await hhJavFreezer.getRewardPerBlock()).to.equal(
                ethers.parseEther("0.05"),
            );
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavFreezer.connect(addr1).pause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set pause", async () => {
            await hhJavFreezer.pause();

            await expect(await hhJavFreezer.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavFreezer.connect(addr1).unpause()).to.be.revertedWith(MANAGER_ERROR);
        });

        it("Should set unpause", async () => {
            await hhJavFreezer.unpause();

            await expect(await hhJavFreezer.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavFreezer.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavFreezer.setAdminAddress(owner.address);

            await expect(await hhJavFreezer.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when setVestingAddress", async () => {
            await expect(
                hhJavFreezer.connect(addr1).setVestingAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setVestingAddress", async () => {
            await hhJavFreezer.setVestingAddress(vesting.address);

            await expect(await hhJavFreezer.vestingAddress()).to.equal(vesting.address);
        });

        it("Should revert when setRewardsDistributorAddress", async () => {
            await expect(
                hhJavFreezer.connect(addr1).setRewardsDistributorAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardsDistributorAddress", async () => {
            await hhJavFreezer.setRewardsDistributorAddress(rewardsDistributor.address);

            await expect(await hhJavFreezer.rewardsDistributorAddress()).to.equal(
                rewardsDistributor.address,
            );
        });

        it("Should revert when addPool", async () => {
            const poolFee = {
                depositFee: 0.5 * 1e4,
                withdrawFee: 0.5 * 1e4,
                claimFee: 0.5 * 1e4,
            };
            await expect(
                hhJavFreezer
                    .connect(addr1)
                    .addPool(erc20Token.target, erc20Token.target, 1, 1, poolFee),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addPool", async () => {
            const fee = {
                depositFee: 1 * 1e4,
                withdrawFee: 1 * 1e4,
                claimFee: 1 * 1e4,
            };
            const baseToken = erc20Token.target;
            const lastRewardBlock = await ethers.provider.getBlockNumber();
            const accRewardPerShare = ethers.parseEther("0.01");

            await hhJavFreezer.addPool(
                baseToken,
                baseToken,
                lastRewardBlock,
                accRewardPerShare,
                fee,
            );

            await expect(await hhJavFreezer.getPoolLength()).to.be.equal(1);

            const poolInfo = await hhJavFreezer.poolInfo(0);
            const poolFee = await hhJavFreezer.poolFee(0);

            await expect(poolInfo[0]).to.be.equal(baseToken);
            await expect(poolInfo[1]).to.be.equal(baseToken);
            await expect(poolInfo[2]).to.be.equal(0);
            await expect(poolInfo[3]).to.be.equal(lastRewardBlock);
            await expect(poolInfo[4]).to.be.equal(accRewardPerShare);
            await expect(poolFee.depositFee).to.be.equal(1 * 1e4);
            await expect(poolFee.withdrawFee).to.be.equal(1 * 1e4);
            await expect(poolFee.claimFee).to.be.equal(1 * 1e4);
        });

        it("Should addPool with lastRewardBlock > blockNumber", async () => {
            const fee = {
                depositFee: 1 * 1e4,
                withdrawFee: 1 * 1e4,
                claimFee: 1 * 1e4,
            };
            const baseToken = erc20Token.target;
            const lastRewardBlock = (await ethers.provider.getBlockNumber()) + 500;
            const accRewardPerShare = ethers.parseEther("0.01");

            await hhJavFreezer.addPool(
                baseToken,
                baseToken,
                lastRewardBlock,
                accRewardPerShare,
                fee,
            );

            await expect(await hhJavFreezer.getPoolLength()).to.be.equal(2);

            const poolInfo = await hhJavFreezer.poolInfo(1);
            const poolFee = await hhJavFreezer.poolFee(0);

            await expect(poolInfo[0]).to.be.equal(baseToken);
            await expect(poolInfo[1]).to.be.equal(baseToken);
            await expect(poolInfo[2]).to.be.equal(0);
            await expect(poolInfo[3]).to.be.equal(lastRewardBlock);
            await expect(poolInfo[4]).to.be.equal(accRewardPerShare);
            await expect(poolFee.depositFee).to.be.equal(1 * 1e4);
            await expect(poolFee.withdrawFee).to.be.equal(1 * 1e4);
            await expect(poolFee.claimFee).to.be.equal(1 * 1e4);
        });

        it("Should revert when setRewardConfiguration", async () => {
            await expect(
                hhJavFreezer.connect(addr1).setRewardConfiguration(1, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardConfiguration", async () => {
            const rewardPerBlock = ethers.parseEther("0.5");
            const updateBlocksInterval = 12345;

            await hhJavFreezer.setRewardConfiguration(rewardPerBlock, updateBlocksInterval);

            const lastBlock = await ethers.provider.getBlockNumber();
            const rewardsConfiguration = await hhJavFreezer.getRewardsConfiguration();

            await expect(rewardsConfiguration.rewardPerBlock).to.be.equal(rewardPerBlock);
            await expect(rewardsConfiguration.lastUpdateBlockNum).to.be.equal(lastBlock);
            await expect(rewardsConfiguration.updateBlocksInterval).to.be.equal(
                updateBlocksInterval,
            );
        });

        it("Should revert when setPoolInfo - admin error", async () => {
            await expect(hhJavFreezer.connect(addr1).setPoolInfo(0, 1, 1)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should revert when setPoolInfo - WrongPool", async () => {
            await expect(hhJavFreezer.setPoolInfo(5, 1, 1)).to.be.revertedWithCustomError(
                hhJavFreezer,
                "WrongPool",
            );
        });

        it("Should setPoolInfo", async () => {
            const _pid = 0;
            const lastRewardBlock = await ethers.provider.getBlockNumber();
            const accRewardPerShare = ethers.parseEther("0.02");

            await hhJavFreezer.setPoolInfo(_pid, lastRewardBlock, accRewardPerShare);

            const poolInfo = await hhJavFreezer.poolInfo(_pid);

            await expect(poolInfo[3]).to.be.equal(lastRewardBlock);
            await expect(poolInfo[4]).to.be.equal(accRewardPerShare);
        });

        it("Should revert when setPoolFee - admin error", async () => {
            const poolFee = {
                depositFee: 0.5 * 1e4,
                withdrawFee: 0.5 * 1e4,
                claimFee: 0.5 * 1e4,
            };
            await expect(hhJavFreezer.connect(addr1).setPoolFee(0, poolFee)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should revert when setPoolFee - WrongPool", async () => {
            const poolFee = {
                depositFee: 0.5 * 1e4,
                withdrawFee: 0.5 * 1e4,
                claimFee: 0.5 * 1e4,
            };
            await expect(hhJavFreezer.setPoolFee(5, poolFee)).to.be.revertedWithCustomError(
                hhJavFreezer,
                "WrongPool",
            );
        });

        it("Should setPoolFee", async () => {
            const _pid = 0;
            const poolFee = {
                depositFee: 5,
                withdrawFee: 5,
                claimFee: 5,
            };

            await hhJavFreezer.setPoolFee(_pid, poolFee);

            const poolFeeInfo = await hhJavFreezer.poolFee(_pid);

            await expect(poolFeeInfo[0]).to.be.equal(5);
            await expect(poolFeeInfo[1]).to.be.equal(5);
            await expect(poolFeeInfo[2]).to.be.equal(5);
        });

        it("Should revert when setLockPeriod - admin error", async () => {
            await expect(hhJavFreezer.connect(addr1).setLockPeriod(1, 1)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should setLockPeriod ", async () => {
            const id_0 = 0;
            const id_1 = 1;
            const durations_0 = 60; //1 min
            const durations_1 = 120; //2 min

            await hhJavFreezer.setLockPeriod(id_0, durations_0);
            await hhJavFreezer.setLockPeriod(id_1, durations_1);

            await expect(await hhJavFreezer.lockPeriod(id_0)).to.be.equal(durations_0);
            await expect(await hhJavFreezer.lockPeriod(id_1)).to.be.equal(durations_1);
        });

        it("Should revert when setLockPeriodMultiplier - admin error", async () => {
            await expect(
                hhJavFreezer.connect(addr1).setLockPeriodMultiplier(1, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setLockPeriodMultiplier ", async () => {
            const id = 0;
            const multiplier = 1e5; //1.00000

            await hhJavFreezer.setLockPeriodMultiplier(id, multiplier);

            await expect(await hhJavFreezer.lockPeriodMultiplier(id)).to.be.equal(multiplier);
        });

        it("Should revert when deposit - pause", async () => {
            await hhJavFreezer.pause();

            await expect(
                hhJavFreezer.connect(addr1).deposit(1, 1, 1),
            ).to.be.revertedWithCustomError(hhJavFreezer, "EnforcedPause");
            await hhJavFreezer.unpause();
        });

        it("Should revert when deposit - WrongPool", async () => {
            await expect(
                hhJavFreezer.connect(addr1).deposit(2, 1, 1),
            ).to.be.revertedWithCustomError(hhJavFreezer, "WrongPool");
        });

        it("Should revert when deposit - invalid lock id", async () => {
            await expect(
                hhJavFreezer.connect(addr1).deposit(0, 2, 1),
            ).to.be.revertedWithCustomError(hhJavFreezer, "WrongLockPeriod");
        });

        it("Should revert when deposit - invalid lock id", async () => {
            await expect(
                hhJavFreezer.connect(addr1).deposit(0, 5, 1),
            ).to.be.revertedWithCustomError(hhJavFreezer, "WrongLockPeriod");
        });

        it("Should revert when deposit - invalid balance", async () => {
            await expect(
                hhJavFreezer.connect(addr1).deposit(0, 0, 1),
            ).to.be.revertedWithCustomError(hhJavFreezer, "InvalidAmount");
        });

        it("Should revert when depositVesting - pause", async () => {
            await hhJavFreezer.pause();

            await expect(
                hhJavFreezer.connect(addr1).depositVesting(addr1.address, 1, 1, 1, 1, 5),
            ).to.be.revertedWithCustomError(hhJavFreezer, "EnforcedPause");
            await hhJavFreezer.unpause();
        });

        it("Should revert when depositVesting - WrongPool", async () => {
            await expect(
                hhJavFreezer.connect(addr1).depositVesting(addr1.address, 2, 1, 1, 1, 5),
            ).to.be.revertedWithCustomError(hhJavFreezer, "WrongPool");
        });

        it("Should revert when depositVesting - only vesting", async () => {
            await expect(
                hhJavFreezer.connect(addr1).depositVesting(addr1.address, 0, 2, 1, 1, 5),
            ).to.be.revertedWithCustomError(hhJavFreezer, "NotAllowed");
        });

        it("Should depositVesting", async () => {
            const pid = 0;
            const amount = ethers.parseEther("10");
            const lockId = 5;
            const depositTimestamp = 123456689;
            const withdrawalTimestamp = 123456789;

            await erc20Token.mint(hhJavFreezer.target, amount);

            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);

            await hhJavFreezer
                .connect(vesting)
                .depositVesting(
                    addr1.address,
                    pid,
                    amount,
                    depositTimestamp,
                    withdrawalTimestamp,
                    lockId,
                );

            const poolInfo = await hhJavFreezer.poolInfo(pid);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, 0);
            const blockNumber = await ethers.provider.getBlockNumber();

            const rewardDebt = (amount * poolInfo[4]) / ethers.parseEther("1");

            await expect(poolInfo[0]).to.be.equal(poolInfoBefore[0]);
            await expect(poolInfo[1]).to.be.equal(poolInfoBefore[1]);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] + amount);
            await expect(poolInfo[3]).to.be.equal(blockNumber);
            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] + amount);
            await expect(userInfo[1]).to.be.equal(userInfoBefore[1] + BigInt(1));
            await expect(userInfo[2]).to.be.equal(userInfoBefore[2]);
            await expect(userDeposit[0]).to.be.equal(amount);
            await expect(userDeposit[1]).to.be.equal(lockId);
            await expect(userDeposit[2]).to.be.equal(depositTimestamp);
            await expect(userDeposit[3]).to.be.equal(withdrawalTimestamp);
            await expect(userDeposit[4]).to.be.equal(0);
            await expect(userDeposit[5]).to.be.equal(rewardDebt);
            await expect(userDeposit[6]).to.be.equal(false);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(tvlBefore + amount);
        });

        it("Should deposit", async () => {
            const pid = 0;
            const lockId = 0;
            const amount = ethers.parseEther("1");
            const lockPeriod = await hhJavFreezer.lockPeriod(lockId);
            const poolFee = await hhJavFreezer.poolFee(pid);

            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhJavFreezer.target, amount);

            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);
            const burnAmount = (amount * poolFee.depositFee) / BigInt(1e4);

            await hhJavFreezer.connect(addr1).deposit(pid, lockId, amount);

            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const poolInfo = await hhJavFreezer.poolInfo(pid);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, 1);
            const blockNumber = await ethers.provider.getBlockNumber();
            const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;

            const rewardDebt = ((amount - burnAmount) * poolInfo[4]) / ethers.parseEther("1");

            await expect(contractBalance).to.be.equal(contractBalanceBefore + amount - burnAmount);
            await expect(poolInfo[0]).to.be.equal(poolInfoBefore[0]);
            await expect(poolInfo[1]).to.be.equal(poolInfoBefore[1]);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] + amount - burnAmount);
            await expect(poolInfo[3]).to.be.equal(blockNumber);
            // await expect(poolInfo[4]).to.be.equal(poolInfoBefore[4]);
            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] + amount - burnAmount);
            await expect(userInfo[1]).to.be.equal(userInfoBefore[1] + BigInt(1));
            await expect(userInfo[2]).to.be.equal(userInfoBefore[2]);
            await expect(userDeposit[0]).to.be.equal(amount - burnAmount);
            await expect(userDeposit[1]).to.be.equal(lockId);
            await expect(userDeposit[2]).to.be.equal(blockTimestamp);
            await expect(userDeposit[3]).to.be.equal(BigInt(blockTimestamp) + lockPeriod);
            await expect(userDeposit[4]).to.be.equal(0);
            await expect(userDeposit[5]).to.be.equal(rewardDebt);
            await expect(userDeposit[6]).to.be.equal(false);
            await expect(await hhJavFreezer.pendingReward(pid, 0, addr1.address)).to.be.equal(0);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(
                tvlBefore + amount - burnAmount,
            );
        });

        it("Should deposit - 2", async () => {
            const pid = 0;
            const lockId = 0;
            const amount = ethers.parseEther("5");
            const lockPeriod = await hhJavFreezer.lockPeriod(lockId);
            const poolFee = await hhJavFreezer.poolFee(pid);

            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhJavFreezer.target, amount);

            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);
            const burnAmount = (amount * poolFee.depositFee) / BigInt(1e4);

            await hhJavFreezer.connect(addr1).deposit(pid, lockId, amount);

            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const poolInfo = await hhJavFreezer.poolInfo(pid);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, 2);
            const blockNumber = await ethers.provider.getBlockNumber();
            const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;

            const rewardDebt = ((amount - burnAmount) * poolInfo[4]) / ethers.parseEther("1");
            const accRewardPerShare = await expect(contractBalance).to.be.equal(
                contractBalanceBefore + amount - burnAmount,
            );
            await expect(poolInfo[0]).to.be.equal(poolInfoBefore[0]);
            await expect(poolInfo[1]).to.be.equal(poolInfoBefore[1]);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] + amount - burnAmount);
            await expect(poolInfo[3]).to.be.equal(blockNumber);
            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] + amount - burnAmount);
            await expect(userInfo[1]).to.be.equal(userInfoBefore[1] + BigInt(1));
            await expect(userInfo[2]).to.be.equal(userInfoBefore[2]);
            await expect(userDeposit[0]).to.be.equal(amount - burnAmount);
            await expect(userDeposit[1]).to.be.equal(lockId);
            await expect(userDeposit[2]).to.be.equal(blockTimestamp);
            await expect(userDeposit[3]).to.be.equal(BigInt(blockTimestamp) + lockPeriod);
            await expect(userDeposit[4]).to.be.equal(0);
            await expect(userDeposit[5]).to.be.equal(rewardDebt);
            await expect(userDeposit[6]).to.be.equal(false);
            await expect(await hhJavFreezer.pendingReward(pid, 2, addr1.address)).to.be.equal(0);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(
                tvlBefore + amount - burnAmount,
            );
        });

        it("Should deposit - 3, with diff lockId", async () => {
            const pid = 0;
            const lockId = 1;
            const amount = ethers.parseEther("5");
            const lockPeriod = await hhJavFreezer.lockPeriod(lockId);
            const poolFee = await hhJavFreezer.poolFee(pid);

            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhJavFreezer.target, amount);

            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);
            const burnAmount = (amount * poolFee.depositFee) / BigInt(1e4);

            await hhJavFreezer.connect(addr1).deposit(pid, lockId, amount);

            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const poolInfo = await hhJavFreezer.poolInfo(pid);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, 3);
            const blockNumber = await ethers.provider.getBlockNumber();
            const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;

            const rewardDebt = ((amount - burnAmount) * poolInfo[4]) / ethers.parseEther("1");
            const accRewardPerShare = await expect(contractBalance).to.be.equal(
                contractBalanceBefore + amount - burnAmount,
            );
            await expect(poolInfo[0]).to.be.equal(poolInfoBefore[0]);
            await expect(poolInfo[1]).to.be.equal(poolInfoBefore[1]);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] + amount - burnAmount);
            await expect(poolInfo[3]).to.be.equal(blockNumber);
            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] + amount - burnAmount);
            await expect(userInfo[1]).to.be.equal(userInfoBefore[1] + BigInt(1));
            await expect(userInfo[2]).to.be.equal(userInfoBefore[2]);
            await expect(userDeposit[0]).to.be.equal(amount - burnAmount);
            await expect(userDeposit[1]).to.be.equal(lockId);
            await expect(userDeposit[2]).to.be.equal(blockTimestamp);
            await expect(userDeposit[3]).to.be.equal(BigInt(blockTimestamp) + lockPeriod);
            await expect(userDeposit[4]).to.be.equal(0);
            await expect(userDeposit[5]).to.be.equal(rewardDebt);
            await expect(userDeposit[6]).to.be.equal(false);
            await expect(await hhJavFreezer.pendingReward(pid, 3, addr1.address)).to.be.equal(0);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(
                tvlBefore + amount - burnAmount,
            );
        });

        it("Should get pendingReward = 0, block = lastRewardBlock", async () => {
            const pid = 0;
            const depositId = 2;

            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const poolInfo = await hhJavFreezer.poolInfo(pid);

            const pendingReward =
                (userDeposit[0] * poolInfo[4]) / ethers.parseEther("1") - userDeposit[5];

            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(pendingReward);
        });

        it("Should get pendingReward, block > lastRewardBlock", async () => {
            const pid = 0;
            const depositId = 1;
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const poolInfo = await hhJavFreezer.poolInfo(pid);

            await helpers.mine(10);
            const blockNumber = await ethers.provider.getBlockNumber();

            const multiplier = BigInt(blockNumber) - poolInfo[3];
            const rewardPerBlock = await hhJavFreezer.getRewardPerBlock();
            const reward = multiplier * rewardPerBlock;
            const accRewardPerShare = poolInfo[4] + (reward * ethers.parseEther("1")) / poolInfo[2];
            const pendingReward =
                (userDeposit[0] * accRewardPerShare) / ethers.parseEther("1") - userDeposit[5];

            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(pendingReward);
        });

        it("Should get pendingReward, block > lastRewardBlock with lock period multiplier", async () => {
            const pid = 0;
            const depositId = 2;
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const poolInfo = await hhJavFreezer.poolInfo(pid);
            const lockMultiplier = BigInt(100005); //1.00005
            await hhJavFreezer.setLockPeriodMultiplier(0, lockMultiplier);

            await helpers.mine(10);
            const blockNumber = await ethers.provider.getBlockNumber();

            const multiplier = BigInt(blockNumber) - poolInfo[3];
            const rewardPerBlock = await hhJavFreezer.getRewardPerBlock();
            const reward = multiplier * rewardPerBlock;
            const accRewardPerShare = poolInfo[4] + (reward * ethers.parseEther("1")) / poolInfo[2];
            let pendingReward =
                (userDeposit[0] * accRewardPerShare) / ethers.parseEther("1") - userDeposit[5];

            pendingReward = (pendingReward * lockMultiplier) / BigInt(1e5);

            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(pendingReward);

            await hhJavFreezer.setLockPeriodMultiplier(0, 1e5);
        });

        it("Should get pendingRewardTotal - 4 deposit", async () => {
            await mine(5);
            const rewards1 = await hhJavFreezer.pendingReward(0, 0, addr1.address);
            const rewards2 = await hhJavFreezer.pendingReward(0, 1, addr1.address);
            const rewards3 = await hhJavFreezer.pendingReward(0, 2, addr1.address);
            const rewards4 = await hhJavFreezer.pendingReward(0, 3, addr1.address);
            await expect(await hhJavFreezer.pendingRewardTotal(0, addr1.address)).to.be.equal(
                rewards1 + rewards2 + rewards3 + rewards4,
            );
        });

        it("Should get getUserLastDepositId", async () => {
            await expect(await hhJavFreezer.getUserLastDepositId(0, addr1.address)).to.be.equal(3);
        });

        it("Should revert when claim - WrongPool", async () => {
            await expect(hhJavFreezer.connect(addr1).claim(2, 1)).to.be.revertedWithCustomError(
                hhJavFreezer,
                "WrongPool",
            );
        });

        it("Should claim", async () => {
            const pid = 0;
            const depositId = 0;
            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDepositBefore = await hhJavFreezer.userDeposits(
                addr1.address,
                pid,
                depositId,
            );

            await hhJavFreezer.connect(addr1).claim(pid, depositId);
            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const pendingRewards = userInfo[2] - userInfoBefore[2];

            await expect(userInfo[2]).to.be.equal(userInfoBefore[2] + pendingRewards);
            await expect(userDeposit[4]).to.be.equal(userDepositBefore[4] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(contractBalanceBefore - pendingRewards);
            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(0);
        });

        it("Should claimAll", async () => {
            const pid = 0;

            await erc20Token.mint(hhJavFreezer.target, ethers.parseEther("10"));
            await helpers.mine(10);

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);

            await hhJavFreezer.connect(addr1).claimAll(pid);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);

            const pendingRewards = userInfo[2] - userInfoBefore[2];
            const claimFee =
                contractBalanceBefore -
                pendingRewards -
                (await erc20Token.balanceOf(hhJavFreezer.target));

            await expect(userInfo[2]).to.be.equal(userInfoBefore[2] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(
                contractBalanceBefore - pendingRewards - claimFee,
            );
            await expect(await hhJavFreezer.pendingRewardTotal(pid, addr1.address)).to.be.equal(0);
        });

        it("Should revert when withdraw - WrongPool", async () => {
            await expect(hhJavFreezer.connect(addr1).withdraw(2, 0)).to.be.revertedWithCustomError(
                hhJavFreezer,
                "WrongPool",
            );
        });

        it("Should revert when withdraw - withdrawalTimestamp > block.timestamp", async () => {
            await expect(hhJavFreezer.connect(addr1).withdraw(0, 2)).to.be.revertedWithCustomError(
                hhJavFreezer,
                "PeriodNotEnded",
            );
        });

        it("Should withdraw ", async () => {
            const pid = 0;
            const depositId = 1;
            const lockId = 0;
            const poolFee = await hhJavFreezer.poolFee(pid);
            await erc20Token.mint(hhJavFreezer.target, ethers.parseEther("10"));
            await helpers.mine(50);

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDepositBefore = await hhJavFreezer.userDeposits(
                addr1.address,
                pid,
                depositId,
            );
            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const depositTokens = userDepositBefore[0];
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);

            await hhJavFreezer.connect(addr1).withdraw(pid, depositId);
            const burnAmount = (depositTokens * poolFee.withdrawFee) / BigInt(1e4);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const poolInfo = await hhJavFreezer.poolInfo(pid);

            const claimAmount = userDeposit[4] - userDepositBefore[4];

            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] - depositTokens);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] - depositTokens);
            await expect(userDeposit[6]).to.be.equal(true);
            await expect(userBalance).to.be.equal(
                userBalanceBefore + depositTokens + claimAmount - burnAmount,
            );
            await expect(contractBalance).to.be.below(
                contractBalanceBefore - depositTokens - claimAmount - burnAmount,
            );
            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(0);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(
                tvlBefore - depositTokens,
            );
        });

        it("Should revert when withdrawVesting - WrongPool", async () => {
            await expect(
                hhJavFreezer
                    .connect(vesting)
                    .withdrawVesting(addr1.address, 2, 0, ethers.parseEther("1")),
            ).to.be.revertedWithCustomError(hhJavFreezer, "WrongPool");
        });

        it("Should revert when withdrawVesting - invalid withdraw amount", async () => {
            await expect(
                hhJavFreezer
                    .connect(vesting)
                    .withdrawVesting(addr1.address, 0, 1, ethers.parseEther("100")),
            ).to.be.revertedWithCustomError(hhJavFreezer, "InvalidAmount");
        });

        it("Should withdrawVesting ", async () => {
            const pid = 0;
            const depositId = 0;
            const lockId = 5;
            await erc20Token.mint(hhJavFreezer.target, ethers.parseEther("10"));
            await helpers.mine(50);
            const withdrawAmount = ethers.parseEther("5");

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDepositBefore = await hhJavFreezer.userDeposits(
                addr1.address,
                pid,
                depositId,
            );
            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);

            await hhJavFreezer
                .connect(addr1)
                .connect(vesting)
                .withdrawVesting(addr1.address, pid, depositId, withdrawAmount);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const poolInfo = await hhJavFreezer.poolInfo(pid);

            const claimAmount = userDeposit[4] - userDepositBefore[4];

            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] - withdrawAmount);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] - withdrawAmount);
            await expect(userDeposit[6]).to.be.equal(false);
            await expect(userBalance).to.be.equal(userBalanceBefore + withdrawAmount + claimAmount);
            await expect(contractBalance).to.be.equal(
                contractBalanceBefore - withdrawAmount - claimAmount,
            );
            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(0);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(
                tvlBefore - withdrawAmount,
            );
        });

        it("Should withdrawVesting full amount", async () => {
            const pid = 0;
            const depositId = 0;
            const lockId = 5;
            await erc20Token.mint(hhJavFreezer.target, ethers.parseEther("10"));
            await helpers.mine(50);
            const withdrawAmount = ethers.parseEther("5");

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDepositBefore = await hhJavFreezer.userDeposits(
                addr1.address,
                pid,
                depositId,
            );
            const poolInfoBefore = await hhJavFreezer.poolInfo(pid);
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);

            await hhJavFreezer
                .connect(addr1)
                .connect(vesting)
                .withdrawVesting(addr1.address, pid, depositId, withdrawAmount);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const poolInfo = await hhJavFreezer.poolInfo(pid);

            const claimAmount = userDeposit[4] - userDepositBefore[4];

            await expect(userInfo[0]).to.be.equal(userInfoBefore[0] - withdrawAmount);
            await expect(poolInfo[2]).to.be.equal(poolInfoBefore[2] - withdrawAmount);
            await expect(userDeposit[6]).to.be.equal(true);
            await expect(userBalance).to.be.equal(userBalanceBefore + withdrawAmount + claimAmount);
            await expect(contractBalance).to.be.equal(
                contractBalanceBefore - withdrawAmount - claimAmount,
            );
            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(0);
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(
                tvlBefore - withdrawAmount,
            );
        });

        it("Should get pendingReward with block.timestamp <= pool.lastRewardBlock", async () => {
            const pid = 0;
            const amount = ethers.parseEther("10");
            const lockId = 5;
            const depositTimestamp = 123456689;
            const withdrawalTimestamp = 123456789;
            const accRewardPerShare = (await hhJavFreezer.poolInfo(pid))[4];

            await erc20Token.mint(hhJavFreezer.target, amount);

            const block = (await ethers.provider.getBlockNumber()) + 500;
            const tvlBefore = await hhJavFreezer.tvl(pid, lockId);

            await hhJavFreezer
                .connect(vesting)
                .depositVesting(
                    addr1.address,
                    pid,
                    amount,
                    depositTimestamp,
                    withdrawalTimestamp,
                    lockId,
                );

            await hhJavFreezer.setPoolInfo(0, block, 0);

            await expect(await hhJavFreezer.pendingRewardTotal(0, addr1.address)).to.be.equal(0);

            await hhJavFreezer.setPoolInfo(
                0,
                await ethers.provider.getBlockNumber(),
                accRewardPerShare,
            );
            await expect(await hhJavFreezer.tvl(pid, lockId)).to.be.equal(tvlBefore + amount);
        });

        it("Should get pendingReward after claim and some blocks", async () => {
            const pid = 0;
            const depositId = 2;

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDepositBefore = await hhJavFreezer.userDeposits(
                addr1.address,
                pid,
                depositId,
            );

            await hhJavFreezer.connect(addr1).claim(pid, depositId);
            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const pendingRewards = userInfo[2] - userInfoBefore[2];
            const burnFee = contractBalanceBefore - contractBalance - pendingRewards;

            await expect(userInfo[2]).to.be.equal(userInfoBefore[2] + pendingRewards);
            await expect(userDeposit[4]).to.be.equal(userDepositBefore[4] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(
                contractBalanceBefore - pendingRewards - burnFee,
            );
            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(0);
        });

        it("Should revert when addRewards", async () => {
            await expect(
                hhJavFreezer.connect(addr1).addRewards(1, 1),
            ).to.be.revertedWithCustomError(hhJavFreezer, "NotAllowed");
        });

        it("Should addRewards", async () => {
            const pid = 0;
            const poolInfo = await hhJavFreezer.poolInfo(pid);
            const totalShares = poolInfo[2];
            const amount = totalShares * BigInt(2);

            await erc20Token.mint(hhJavFreezer.target, amount);

            await hhJavFreezer.connect(rewardsDistributor).addRewards(pid, amount);

            const productsRewardsInfo = await hhJavFreezer.productsRewardsInfo(pid);

            await expect(productsRewardsInfo[0]).to.be.equal(amount);
            await expect(productsRewardsInfo[1]).to.be.equal(
                (amount * ethers.parseEther("1")) / totalShares,
            );
        });

        it("Should get pendingReward after addRewards and claim, skip some blocks", async () => {
            const pid = 0;
            const depositId = 2;

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDepositBefore = await hhJavFreezer.userDeposits(
                addr1.address,
                pid,
                depositId,
            );

            await hhJavFreezer.connect(addr1).claim(pid, depositId);
            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);
            const userDeposit = await hhJavFreezer.userDeposits(addr1.address, pid, depositId);
            const pendingRewards = userInfo[2] - userInfoBefore[2];
            const burnFee = contractBalanceBefore - contractBalance - pendingRewards;

            await expect(userInfo[2]).to.be.equal(userInfoBefore[2] + pendingRewards);
            await expect(userDeposit[4]).to.be.equal(userDepositBefore[4] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(
                contractBalanceBefore - pendingRewards - burnFee,
            );
            await expect(
                await hhJavFreezer.pendingReward(pid, depositId, addr1.address),
            ).to.be.equal(0);
        });

        it("Should get pendingRewardByLockId - 3 deposit", async () => {
            const rewards1 = await hhJavFreezer.pendingReward(0, 0, addr1.address);
            const rewards2 = await hhJavFreezer.pendingReward(0, 1, addr1.address);
            const rewards3 = await hhJavFreezer.pendingReward(0, 2, addr1.address);
            const rewards4 = await hhJavFreezer.pendingReward(0, 3, addr1.address);
            await expect(await hhJavFreezer.pendingRewardByLockId(0, 0, addr1.address)).to.be.equal(
                rewards1 + rewards2 + rewards3,
            );
            await expect(await hhJavFreezer.pendingRewardByLockId(0, 1, addr1.address)).to.be.equal(
                rewards4,
            );
        });

        it("Should claimAllByByLockId", async () => {
            const pid = 0;
            const lockId = 0;

            await erc20Token.mint(hhJavFreezer.target, ethers.parseEther("10"));
            await helpers.mine(10);

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfoBefore = await hhJavFreezer.userInfo(addr1.address, pid);

            await hhJavFreezer.connect(addr1).claimAllByByLockId(pid, lockId);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFreezer.target);
            const userInfo = await hhJavFreezer.userInfo(addr1.address, pid);

            const pendingRewards = userInfo[2] - userInfoBefore[2];
            const burnFee = contractBalanceBefore - contractBalance - pendingRewards;

            await expect(userInfo[2]).to.be.equal(userInfoBefore[2] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(
                contractBalanceBefore - pendingRewards - burnFee,
            );

            await expect(
                await hhJavFreezer.pendingRewardByLockId(0, lockId, addr1.address),
            ).to.be.equal(0);

            const rewards4 = await hhJavFreezer.pendingReward(0, 3, addr1.address);
            const rewards5 = await hhJavFreezer.pendingReward(0, 4, addr1.address);
            await expect(await hhJavFreezer.pendingRewardTotal(pid, addr1.address)).to.be.equal(
                rewards4 + rewards5,
            );
        });
    });
});
