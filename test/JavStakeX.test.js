const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { min } = require("hardhat/internal/util/bigint");
const { ADMIN_ERROR } = require("./common/constanst");
const { deployTokenFixture } = require("./common/mocks");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("JavStakeX contract", () => {
    let hhJavStakeX;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let bot;
    let erc20Token;
    let rewardsDistributor;
    let poolError;

    before(async () => {
        const javStakeX = await ethers.getContractFactory("JavStakeX");
        [owner, addr1, addr2, addr3, bot, rewardsDistributor, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        const rewardPerBlock = ethers.parseEther("0.05");
        const rewardUpdateBlocksInterval = 864000;

        hhJavStakeX = await upgrades.deployProxy(
            javStakeX,
            [rewardPerBlock, rewardUpdateBlocksInterval, rewardsDistributor.address],

            {
                initializer: "initialize",
            },
        );

        poolError = "JavStakeX: Unknown pool";
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

        it("Should revert when setRewardsDistributorAddress", async () => {
            await expect(
                hhJavStakeX.connect(addr1).setRewardsDistributorAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardsDistributorAddress", async () => {
            await hhJavStakeX.setRewardsDistributorAddress(rewardsDistributor.address);

            await expect(await hhJavStakeX.rewardsDistributorAddress()).to.equal(
                rewardsDistributor.address,
            );
        });

        it("Should revert when addPool", async () => {
            await expect(
                hhJavStakeX
                    .connect(addr1)
                    .addPool(erc20Token.target, erc20Token.target, 1, 1, ethers.parseEther("1")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addPool", async () => {
            const minStakeAmount = ethers.parseEther("1");
            const lastRewardBlock = await ethers.provider.getBlockNumber();
            const accRewardPerShare = ethers.parseEther("0.00");

            await hhJavStakeX.addPool(
                erc20Token.target,
                erc20Token.target,
                lastRewardBlock,
                accRewardPerShare,
                minStakeAmount,
            );
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

        it("Should revert when setRewardConfiguration", async () => {
            await expect(
                hhJavStakeX.connect(addr1).setRewardConfiguration(1, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardConfiguration", async () => {
            const rewardPerBlock = ethers.parseEther("0.05");
            const updateBlocksInterval = 12345;

            await hhJavStakeX.setRewardConfiguration(rewardPerBlock, updateBlocksInterval);

            const lastBlock = await ethers.provider.getBlockNumber();
            const rewardsConfiguration = await hhJavStakeX.getRewardsConfiguration();

            await expect(rewardsConfiguration.rewardPerBlock).to.be.equal(rewardPerBlock);
            await expect(rewardsConfiguration.lastUpdateBlockNum).to.be.equal(lastBlock);
            await expect(rewardsConfiguration.updateBlocksInterval).to.be.equal(
                updateBlocksInterval,
            );
        });

        it("Should revert when setPoolInfo - admin error", async () => {
            await expect(hhJavStakeX.connect(addr1).setPoolInfo(0, 1, 1)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should revert when setPoolInfo - poolError", async () => {
            await expect(hhJavStakeX.setPoolInfo(5, 1, 1)).to.be.revertedWith(poolError);
        });

        it("Should setPoolInfo", async () => {
            const _pid = 0;
            const lastRewardBlock = await ethers.provider.getBlockNumber();
            const accRewardPerShare = ethers.parseEther("0.02");

            await hhJavStakeX.setPoolInfo(_pid, lastRewardBlock, accRewardPerShare);

            const poolInfo = await hhJavStakeX.poolInfo(_pid);

            await expect(poolInfo[3]).to.be.equal(lastRewardBlock);
            await expect(poolInfo[4]).to.be.equal(accRewardPerShare);
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

            const rewardsPerShare = poolInfo.accRewardPerShare;
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
            await expect(poolInfo.rewardsPerShare).to.be.equal(0);
            await expect(userInfo.shares).to.be.equal(userInfoBefore.shares + stakeAmount);
            await expect(userInfo.blockRewardDebt).to.be.equal(user1RewardDebt);
            await expect(userInfo.productsRewardDebt).to.be.equal(0);

            await expect(await hhJavStakeX.pendingReward(pid, addr1.address)).to.be.equal(0);
        });

        it("Should get pendingReward addr1 = 0", async () => {
            await expect(await hhJavStakeX.pendingReward(0, addr1.address)).to.be.equal(0);
        });

        it("Should stake - add amount", async () => {
            const stakeAmount = ethers.parseEther("3");
            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const pid = 0;
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr1.address);

            await erc20Token.connect(addr1).approve(hhJavStakeX.target, stakeAmount);
            await hhJavStakeX.connect(addr1).stake(pid, stakeAmount);

            const userRewards =
                (await erc20Token.balanceOf(addr1.address)) - balanceBeforeAddr1 + stakeAmount;
            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr1.address);

            const rewardsPerShare = poolInfo.accRewardPerShare;
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
            await expect(poolInfo.rewardsPerShare).to.be.equal(0);
            await expect(userInfo.shares).to.be.equal(userInfoBefore.shares + stakeAmount);
            await expect(userInfo.blockRewardDebt).to.be.equal(user1RewardDebt);
            await expect(userInfo.productsRewardDebt).to.be.equal(0);
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

            const rewardsPerShare = poolInfo.accRewardPerShare;
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
            await expect(poolInfo.rewardsPerShare).to.be.equal(0);
            await expect(userInfo.shares).to.be.equal(userInfoBefore.shares + stakeAmount);
            await expect(userInfo.blockRewardDebt).to.be.equal(user1RewardDebt);
            await expect(userInfo.productsRewardDebt).to.be.equal(0);
        });

        it("Should claim - with rewards", async () => {
            const rewards = ethers.parseEther("10");
            const pid = 0;

            await erc20Token.mint(hhJavStakeX.target, rewards);

            const balanceBeforeAddr2 = await erc20Token.balanceOf(addr2.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr2.address);

            await hhJavStakeX.connect(addr2).claim(pid);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userRewards = (await erc20Token.balanceOf(addr2.address)) - balanceBeforeAddr2;

            const userInfo = await hhJavStakeX.userInfo(pid, addr2.address);
            const userRewardDebt =
                (userInfo.shares * poolInfo.accRewardPerShare) / ethers.parseEther("1");

            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract - userRewards,
            );
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(
                balanceBeforeAddr2 + userRewards,
            );
            await expect(userInfo.totalClaims).to.be.equal(
                userInfoBefore.totalClaims + userRewards,
            );
            await expect(userInfo.blockRewardDebt).to.be.equal(userRewardDebt);
            await expect(userInfo.productsRewardDebt).to.be.equal(0);
        });

        it("Should claimAll - with rewards", async () => {
            const pid = 0;

            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);

            await hhJavStakeX.connect(addr1).claimAll();

            const userRewards = (await erc20Token.balanceOf(addr1.address)) - balanceBeforeAddr1;

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

        it("Should unstake", async () => {
            const pid = 0;

            const balanceBeforeAddr1 = await erc20Token.balanceOf(addr1.address);
            const balanceBeforeContract = await erc20Token.balanceOf(hhJavStakeX.target);
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, addr1.address);

            await hhJavStakeX.connect(addr1).unstake(pid);

            const userRewards =
                (await erc20Token.balanceOf(addr1.address)) -
                balanceBeforeAddr1 -
                userInfoBefore.shares;

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const userInfo = await hhJavStakeX.userInfo(pid, addr1.address);

            await expect(await erc20Token.balanceOf(addr1.address)).to.be.equal(
                balanceBeforeAddr1 + userInfoBefore.shares + userRewards,
            );
            await expect(await erc20Token.balanceOf(hhJavStakeX.target)).to.be.equal(
                balanceBeforeContract - userInfoBefore.shares - userRewards,
            );
            await expect(userInfo.shares).to.be.equal(0);
            await expect(userInfo.blockRewardDebt).to.be.equal(0);
            await expect(userInfo.productsRewardDebt).to.be.equal(0);
            await expect(poolInfo.totalShares).to.be.equal(
                poolInfoBefore.totalShares - userInfoBefore.shares,
            );
        });

        it("Should get apr", async () => {
            const pid = 0;
            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const rewardsPerBlock = await hhJavStakeX.getRewardPerBlock();
            const apr =
                ((rewardsPerBlock * BigInt(1051200) + poolInfo.rewardsAmount) *
                    ethers.parseEther("1")) /
                poolInfo.totalShares;

            await expect(await hhJavStakeX.apr(pid)).to.be.equal(apr);
        });

        it("Should revert when addRewards", async () => {
            await expect(hhJavStakeX.connect(addr1).addRewards(1, 1)).to.be.revertedWith(
                "JavFreezer: only rewardsDistributor",
            );
        });

        it("Should addRewards", async () => {
            const pid = 0;
            const poolInfoBefore = await hhJavStakeX.poolInfo(pid);
            const amount = poolInfoBefore.totalShares * BigInt(2);

            await erc20Token.mint(hhJavStakeX.target, amount);

            await hhJavStakeX.connect(rewardsDistributor).addRewards(pid, amount);

            const poolInfo = await hhJavStakeX.poolInfo(pid);

            await expect(poolInfoBefore.totalShares).to.be.equal(poolInfo.totalShares);
            await expect(poolInfo.rewardsAmount).to.be.equal(amount);
            await expect(poolInfo.rewardsPerShare).to.be.equal(
                (poolInfo.rewardsAmount * ethers.parseEther("1")) / poolInfo.totalShares,
            );
        });

        it("Should get pendingReward after addRewards and claim, skip some blocks", async () => {
            const pid = 0;
            const address = addr2.address;

            const userBalanceBefore = await erc20Token.balanceOf(address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavStakeX.target);
            const userInfoBefore = await hhJavStakeX.userInfo(pid, address);

            await hhJavStakeX.connect(addr2).claim(pid);
            const userBalance = await erc20Token.balanceOf(address);
            const contractBalance = await erc20Token.balanceOf(hhJavStakeX.target);
            const userInfo = await hhJavStakeX.userInfo(pid, address);
            const pendingRewards = userBalance - userBalanceBefore;

            await expect(userInfo.totalClaims).to.be.equal(
                userInfoBefore.totalClaims + pendingRewards,
            );
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(contractBalanceBefore - pendingRewards);
            await expect(await hhJavStakeX.pendingReward(pid, address)).to.be.equal(0);

            mine(5);

            await expect(await hhJavStakeX.pendingReward(pid, address)).to.be.not.equal(0);
        });

        it("Should get pendingReward with block.timestamp <= pool.lastRewardBlock", async () => {
            const pid = 0;
            const accRewardPerShare = (await hhJavStakeX.poolInfo(pid)).accRewardPerShare;

            const block = (await ethers.provider.getBlockNumber()) + 500;
            await hhJavStakeX.setPoolInfo(0, block, 0);

            await expect(await hhJavStakeX.pendingReward(0, addr1.address)).to.be.equal(0);

            await hhJavStakeX.setPoolInfo(
                pid,
                await ethers.provider.getBlockNumber(),
                accRewardPerShare,
            );
        });

        it("Should get apr after added productsRewards", async () => {
            const pid = 0;

            const stakeAmount = ethers.parseEther("500");

            await erc20Token.mint(addr1.address, stakeAmount);
            await erc20Token.connect(addr1).approve(hhJavStakeX.target, stakeAmount);
            await hhJavStakeX.connect(addr1).stake(pid, stakeAmount);

            const poolInfo = await hhJavStakeX.poolInfo(pid);
            const rewardsPerBlock = await hhJavStakeX.getRewardPerBlock();
            const apr =
                ((rewardsPerBlock * BigInt(1051200) + poolInfo.rewardsAmount) *
                    ethers.parseEther("1")) /
                poolInfo.totalShares;

            await expect(await hhJavStakeX.apr(pid)).to.be.equal(apr);
        });
    });
});
