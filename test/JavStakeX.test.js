const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { min } = require("hardhat/internal/util/bigint");
const { ADMIN_ERROR } = require("./common/constanst");
const { deployTokenFixture } = require("./common/mocks");

describe("JavStakeX contract", () => {
    let hhJavStakeX;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let erc20Token;

    before(async () => {
        const javStakeX = await ethers.getContractFactory("JavStakeX");
        [owner, addr1, addr2, addr3, bot, serviceSigner, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);

        hhJavStakeX = await upgrades.deployProxy(
            javStakeX,
            [],

            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavStakeX.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavStakeX.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavStakeX.paused()).to.equal(false);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavStakeX.connect(addr1).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhJavStakeX.pause();

            await expect(await hhJavStakeX.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavStakeX.connect(addr1).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhJavStakeX.unpause();

            await expect(await hhJavStakeX.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavStakeX.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavStakeX.setAdminAddress(owner.address);

            await expect(await hhJavStakeX.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when grantRole", async () => {
            await expect(
                hhJavStakeX
                    .connect(addr1)
                    .grantRole(ethers.encodeBytes32String("0x02"), bot.address),
            ).to.be.revertedWithCustomError(hhJavStakeX, "AccessControlUnauthorizedAccount");
        });

        it("Should grantRole", async () => {
            await hhJavStakeX.grantRole(ethers.encodeBytes32String("0x02"), bot.address);

            await expect(
                await hhJavStakeX.hasRole(ethers.encodeBytes32String("0x02"), bot.address),
            ).to.be.equal(true);
        });

        it("Should revert when addPool", async () => {
            await expect(
                hhJavStakeX
                    .connect(addr1)
                    .addPool(erc20Token.target, erc20Token.target, ethers.parseEther("1")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addPool", async () => {
            const minStakeAmount = ethers.parseEther("1");

            await hhJavStakeX.addPool(erc20Token.target, erc20Token.target, minStakeAmount);
            const poolInfo = await hhJavStakeX.poolInfo(0);

            await expect(await hhJavStakeX.getPoolLength()).to.be.equal(1);
            await expect(poolInfo.baseToken).to.be.equal(erc20Token.target);
            await expect(poolInfo.rewardToken).to.be.equal(erc20Token.target);
            await expect(poolInfo.totalShares).to.be.equal(0);
            await expect(poolInfo.rewardsAmount).to.be.equal(0);
            await expect(poolInfo.rewardsPerShare).to.be.equal(0);
            await expect(poolInfo.minStakeAmount).to.be.equal(minStakeAmount);
        });

        it("Should getPoolLength", async () => {
            await expect(await hhJavStakeX.getPoolLength()).to.be.equal(1);
        });

        it("Should reverted when updateRewards", async () => {
            await expect(
                hhJavStakeX.connect(addr1).updateRewards(1, 2),
            ).to.be.revertedWithCustomError(hhJavStakeX, "AccessControlUnauthorizedAccount");
        });

        it("Should updateRewards", async () => {
            const rewards = ethers.parseEther("2");
            const pid = 0;
            await erc20Token.mint(hhJavStakeX.target, rewards);

            await hhJavStakeX.connect(bot).updateRewards(pid, rewards);

            const poolInfo = await hhJavStakeX.poolInfo(pid);

            await expect(poolInfo.baseToken).to.be.equal(erc20Token.target);
            await expect(poolInfo.rewardToken).to.be.equal(erc20Token.target);
            await expect(poolInfo.totalShares).to.be.equal(0);
            await expect(poolInfo.rewardsAmount).to.be.equal(rewards);
            await expect(poolInfo.rewardsPerShare).to.be.equal(0);
            await expect(poolInfo.minStakeAmount).to.be.equal(ethers.parseEther("1"));
        });

        it("Should reverted when stake - amount < minAmount", async () => {
            await expect(hhJavStakeX.connect(addr1).stake(0, 2)).to.be.revertedWith(
                "JavStakeX: invalid amount for stake",
            );
        });

        it("Should reverted when stake - balance < amount", async () => {
            const poolInfo = await hhJavStakeX.poolInfo(0);
            await expect(
                hhJavStakeX.connect(addr1).stake(0, poolInfo.minStakeAmount),
            ).to.be.revertedWith("JavStakeX: invalid balance for stake");
        });

        it("Should stake - first time addr1", async () => {
            await erc20Token.mint(addr1.address, ethers.parseEther("20"));
            const stakeAmount = ethers.parseEther("2");
            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const pid = 0;
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr1.address);

            await erc20Token.connect(addr1).approve(hhJavStakeX.target, stakeAmount);
            await hhJavStakeX.connect(addr1).stake(pid, stakeAmount);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr1.address);

            const rewardsPerShare =
                (poolInfo.rewardsAmount * ethers.parseEther("1")) / poolInfo.totalShares;
            const user1RewardDebt = (userInfo.shares * rewardsPerShare) / ethers.parseEther("1");

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract + stakeAmount,
            );
            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                balanceBeforeAddr1 - stakeAmount,
            );
            await expect(poolInfo.totalShares).to.be.equal(
                poolInfoBefore.totalShares + stakeAmount,
            );
            await expect(poolInfo.rewardsPerShare).to.be.equal(rewardsPerShare);
            await expect(userInfo.shares).to.be.equal(userInfoBefore.shares + stakeAmount);
            await expect(userInfo.rewardDebt).to.be.equal(user1RewardDebt);
        });

        it("Should get pendingReward addr1 = 0", async () => {
            await expect(await hhJavStakeX.pendingReward(0, addr1.address)).to.be.equal(0);
        });

        it("Should claim without rewards", async () => {
            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);

            await hhJavStakeX.connect(addr1).claim(0);

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract,
            );
            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(balanceBeforeAddr1);
        });

        it("Should claimAll without rewards", async () => {
            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);

            await hhJavStakeX.connect(addr1).claimAll();

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract,
            );
            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(balanceBeforeAddr1);
        });

        it("Should get pendingReward after distribution", async () => {
            const rewards = ethers.parseEther("3");
            const pid = 0;

            await erc20Token.mint(hhJavStakeX.target, rewards);
            await hhJavStakeX.connect(bot).updateRewards(pid, rewards);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr1.address);

            const userRewards =
                (userInfo.shares * poolInfo.rewardsPerShare) / ethers.parseEther("1") -
                userInfo.rewardDebt;

            await expect(await hhJavStakeX.pendingReward(pid, addr1.address)).to.be.equal(
                userRewards,
            );
        });

        it("Should stake - add amount", async () => {
            const stakeAmount = ethers.parseEther("3");
            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const pid = 0;
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr1.address);
            const userRewards = await hhJavStakeX.pendingReward(pid, addr1.address);

            await erc20Token.connect(addr1).approve(hhJavStakeX.target, stakeAmount);
            await hhJavStakeX.connect(addr1).stake(pid, stakeAmount);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr1.address);

            const rewardsPerShare =
                (poolInfo.rewardsAmount * ethers.parseEther("1")) / poolInfo.totalShares;
            const user1RewardDebt = (userInfo.shares * rewardsPerShare) / ethers.parseEther("1");

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract + stakeAmount - userRewards,
            );
            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                balanceBeforeAddr1 - stakeAmount + userRewards,
            );
            await expect(poolInfo.totalShares).to.be.equal(
                poolInfoBefore.totalShares + stakeAmount,
            );
            await expect(poolInfo.rewardsPerShare).to.be.equal(rewardsPerShare);
            await expect(userInfo.shares).to.be.equal(userInfoBefore.shares + stakeAmount);
            await expect(userInfo.rewardDebt).to.be.equal(user1RewardDebt);
        });

        it("Should stake - from another address", async () => {
            await erc20Token.mint(addr2.address, ethers.parseEther("10"));
            const stakeAmount = ethers.parseEther("5");
            const balanceBeforeAddr2 = await erc20Token.balanceOf(addr2.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const pid = 0;
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr2.address);

            await erc20Token.connect(addr2).approve(hhJavStakeX.target, stakeAmount);
            await hhJavStakeX.connect(addr2).stake(pid, stakeAmount);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr2.address);

            const rewardsPerShare =
                (poolInfo.rewardsAmount * ethers.parseEther("1")) / poolInfo.totalShares;
            const user1RewardDebt = (userInfo.shares * rewardsPerShare) / ethers.parseEther("1");

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract + stakeAmount,
            );
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(
                balanceBeforeAddr2 - stakeAmount,
            );
            await expect(poolInfo.totalShares).to.be.equal(
                poolInfoBefore.totalShares + stakeAmount,
            );
            await expect(poolInfo.rewardsPerShare).to.be.equal(rewardsPerShare);
            await expect(userInfo.shares).to.be.equal(userInfoBefore.shares + stakeAmount);
            await expect(userInfo.rewardDebt).to.be.equal(user1RewardDebt);
        });

        it("Should claim - with rewards", async () => {
            const rewards = ethers.parseEther("10");
            const pid = 0;

            await erc20Token.mint(hhJavStakeX.target, rewards);
            await hhJavStakeX.connect(bot).updateRewards(pid, rewards);

            const balanceBeforeAddr2 = await erc20Token.balanceOf(addr2.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr2.address);

            const userRewards = await hhJavStakeX.pendingReward(pid, addr2.address);
            await hhJavStakeX.connect(addr2).claim(pid);

            const userInfo = await hhJavStakeX.userInfo(pid, addr2.address);
            const userRewardDebt =
                (userInfo.shares * poolInfo.rewardsPerShare) / ethers.parseEther("1");

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract - userRewards,
            );
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(
                balanceBeforeAddr2 + userRewards,
            );
            await expect(userInfo.totalClaims).to.be.equal(
                userInfoBefore.totalClaims + userRewards,
            );
            await expect(userInfo.rewardDebt).to.be.equal(userRewardDebt);
        });

        it("Should claimAll - with rewards", async () => {
            const pid = 0;

            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);

            const userRewards = await hhJavStakeX.pendingReward(pid, addr1.address);
            await hhJavStakeX.connect(addr1).claimAll();

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract - userRewards,
            );
            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                balanceBeforeAddr1 + userRewards,
            );
        });

        it("Should revert when unstake - user.shares = 0", async () => {
            const pid = 0;

            await expect(hhJavStakeX.connect(addr3).unstake(pid)).to.be.revertedWith(
                "JavStakeX: user amount is 0",
            );
        });

        it("Should unstake without rewards", async () => {
            const pid = 0;
            const userRewards = await hhJavStakeX.pendingReward(pid, addr1.address);
            await expect(userRewards).to.be.equal(0);

            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr1.address);

            await hhJavStakeX.connect(addr1).unstake(pid);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr1.address);

            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                balanceBeforeAddr1 + userInfoBefore.shares,
            );
            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract - userInfoBefore.shares,
            );
            await expect(userInfo.shares).to.be.equal(0);
            await expect(userInfo.rewardDebt).to.be.equal(0);
            await expect(poolInfo.totalShares).to.be.equal(
                poolInfoBefore.totalShares - userInfoBefore.shares,
            );
        });

        it("Should unstake with rewards", async () => {
            const pid = 0;
            const rewards = ethers.parseEther("10");

            await erc20Token.mint(hhJavStakeX.target, rewards);
            await erc20Token.mint(hhJavStakeX.target, rewards);
            await hhJavStakeX.connect(bot).updateRewards(pid, rewards);

            const userRewards = await hhJavStakeX.pendingReward(pid, addr2.address);
            await expect(userRewards > 0);

            const balanceBeforeAddr2 = await erc20Token.balanceOf(addr2.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr2.address);

            await hhJavStakeX.connect(addr2).unstake(pid);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr2.address);

            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(
                balanceBeforeAddr2 + userInfoBefore.shares + userRewards,
            );
            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract - userInfoBefore.shares - userRewards,
            );
            await expect(userInfo.shares).to.be.equal(0);
            await expect(userInfo.rewardDebt).to.be.equal(0);
            await expect(poolInfo.totalShares).to.be.equal(
                poolInfoBefore.totalShares - userInfoBefore.shares,
            );
        });
    });
});
