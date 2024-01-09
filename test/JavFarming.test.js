const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR } = require("./common/constanst");
const { deployTokenFixture, deployUniswapFixture, deployToken2Fixture } = require("./common/mocks");

describe("JavFarming contract", () => {
    let hhJavFarming;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let nonZeroAddress;
    let erc20Token;
    let erc20Token2;
    let wdfiToken;
    let uniswapFactory;
    let uniswapRouter;
    let uniswapPairContract;
    let basePair;
    let pair2;
    let poolError;
    let lockError;

    before(async () => {
        const javFarming = await ethers.getContractFactory("JavFarming");
        [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        const data = await helpers.loadFixture(deployUniswapFixture);
        [wdfiToken, uniswapFactory, uniswapRouter, uniswapPairContract] = Object.values(data);

        const rewardPerBlock = ethers.parseEther("0.05");
        const startBlock = 10;

        hhJavFarming = await upgrades.deployProxy(
            javFarming,
            [erc20Token.target, wdfiToken.target, uniswapRouter.target, rewardPerBlock, startBlock],

            {
                initializer: "initialize",
            },
        );

        // create pairs
        await uniswapFactory.createPair(erc20Token.target, wdfiToken.target);
        let allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        basePair = uniswapPairContract.attach(pairCreated);

        await uniswapFactory.createPair(erc20Token.target, erc20Token2.target);
        allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated2 = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        pair2 = uniswapPairContract.attach(pairCreated2);

        // mint tokens
        const amount = ethers.parseEther("200");
        await erc20Token.mint(hhJavFarming.target, amount);

        poolError = "JavFarming: Unknown pool";
        lockError = "JavFarming: invalid lock period";

        // add liquidity
        const amountWeth = ethers.parseEther("500");
        const amount0 = ethers.parseEther("500");
        await wdfiToken.deposit({ value: amountWeth });
        await erc20Token.mint(owner.address, amount0);
        await erc20Token.mint(owner.address, amount0);
        await erc20Token2.mint(owner.address, amount0);

        await wdfiToken.approve(uniswapRouter.target, ethers.parseEther("100000"));
        await erc20Token.approve(uniswapRouter.target, ethers.parseEther("100000"));
        await erc20Token2.approve(uniswapRouter.target, ethers.parseEther("100000"));

        await uniswapRouter.addLiquidity(
            erc20Token.target,
            wdfiToken.target,
            amount0,
            amountWeth,
            1,
            1,
            owner.address,
            // wait time
            "999999999999999999999999999999",
        );

        await uniswapRouter.addLiquidity(
            erc20Token.target,
            erc20Token2.target,
            amount0,
            amount0,
            1,
            1,
            owner.address,
            // wait time
            "999999999999999999999999999999",
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavFarming.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavFarming.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavFarming.paused()).to.equal(false);
        });

        it("Should set the right rewardToken", async () => {
            await expect(await hhJavFarming.rewardToken()).to.equal(erc20Token.target);
        });

        it("Should set the right wdfiAddress", async () => {
            await expect(await hhJavFarming.wdfiAddress()).to.equal(wdfiToken.target);
        });

        it("Should set the right routerAddress", async () => {
            await expect(await hhJavFarming.routerAddress()).to.equal(uniswapRouter.target);
        });

        it("Should set the right startBlock", async () => {
            await expect(await hhJavFarming.startBlock()).to.equal(10);
        });

        it("Should set the right rewardPerBlock", async () => {
            await expect(await hhJavFarming.getRewardPerBlock()).to.equal(
                ethers.parseEther("0.05"),
            );
        });

        it("Should set the right AllowedPairs", async () => {
            const pairs = await hhJavFarming.getAllowedPairs();
            await expect(pairs[0]).to.equal(wdfiToken.target);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavFarming.connect(addr1).pause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set pause", async () => {
            await hhJavFarming.pause();

            await expect(await hhJavFarming.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavFarming.connect(addr1).unpause()).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set unpause", async () => {
            await hhJavFarming.unpause();

            await expect(await hhJavFarming.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavFarming.connect(addr1).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavFarming.setAdminAddress(owner.address);

            await expect(await hhJavFarming.adminAddress()).to.equal(owner.address);
        });

        it("Should revert when addAllowedPair", async () => {
            await expect(
                hhJavFarming.connect(addr1).addAllowedPair(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should addAllowedPair", async () => {
            await hhJavFarming.addAllowedPair(erc20Token2.target);
            const pairs = await hhJavFarming.getAllowedPairs();

            await expect(pairs.length).to.equal(2);
            await expect(pairs[1]).to.equal(erc20Token2.target);
        });

        it("Should revert when removeAllowedPair", async () => {
            await expect(
                hhJavFarming.connect(addr1).removeAllowedPair(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should removeAllowedPair", async () => {
            await hhJavFarming.removeAllowedPair(erc20Token2.target);

            const pairs = await hhJavFarming.getAllowedPairs();

            await expect(pairs.length).to.equal(1);
            await expect(pairs[0]).to.equal(wdfiToken.target);
        });

        it("Should revert when setRewardToken", async () => {
            await expect(
                hhJavFarming.connect(addr1).setRewardToken(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardToken", async () => {
            await hhJavFarming.setRewardToken(erc20Token.target);

            await expect(await hhJavFarming.rewardToken()).to.equal(erc20Token.target);
        });

        it("Should revert when setStartBlock", async () => {
            await expect(hhJavFarming.connect(addr1).setStartBlock(15)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should setStartBlock", async () => {
            await hhJavFarming.setStartBlock(15);

            await expect(await hhJavFarming.startBlock()).to.equal(15);
        });

        it("Should revert when setWDFIAddress", async () => {
            await expect(
                hhJavFarming.connect(addr1).setWDFIAddress(wdfiToken.target),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setWDFIAddress", async () => {
            await hhJavFarming.setWDFIAddress(wdfiToken.target);

            await expect(await hhJavFarming.wdfiAddress()).to.equal(wdfiToken.target);
        });

        it("Should revert when setRouterAddress", async () => {
            await expect(
                hhJavFarming.connect(addr1).setRouterAddress(nonZeroAddress),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRouterAddress", async () => {
            await hhJavFarming.setRouterAddress(uniswapRouter.target);

            await expect(await hhJavFarming.routerAddress()).to.equal(uniswapRouter.target);
        });

        it("Should revert when setRewardConfiguration", async () => {
            await expect(
                hhJavFarming.connect(addr1).setRewardConfiguration(1, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setRewardConfiguration", async () => {
            const rewardPerBlock = ethers.parseEther("0.05");
            const updateBlocksInterval = 12345;

            await hhJavFarming.setRewardConfiguration(rewardPerBlock, updateBlocksInterval);

            const lastBlock = await ethers.provider.getBlockNumber();
            const rewardsConfiguration = await hhJavFarming.getRewardsConfiguration();

            await expect(rewardsConfiguration.rewardPerBlock).to.be.equal(rewardPerBlock);
            await expect(rewardsConfiguration.lastUpdateBlockNum).to.be.equal(lastBlock);
            await expect(rewardsConfiguration.updateBlocksInterval).to.be.equal(
                updateBlocksInterval,
            );
        });

        it("Should revert when addPool - admin error", async () => {
            await expect(
                hhJavFarming.connect(addr1).addPool(1, erc20Token.target),
            ).to.be.revertedWith(ADMIN_ERROR);
        });
        it("Should revert when addPool with random pair", async () => {
            await uniswapFactory.createPair(erc20Token2.target, wdfiToken.target);
            const allPairsLength = await uniswapFactory.allPairsLength();
            const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));

            const erc20Token22wdfiToken = uniswapPairContract.attach(pairCreated);
            await expect(hhJavFarming.addPool(1, erc20Token22wdfiToken.target)).to.be.revertedWith(
                "JavFarming: not a JAV pair",
            );
        });

        it("Should addPool when blockNumber > startBlock", async () => {
            const blockNumber = BigInt(await ethers.provider.getBlockNumber());
            const allocPoint = ethers.parseEther("2");

            await hhJavFarming.addPool(allocPoint, basePair.target);

            await expect(await hhJavFarming.getPoolLength()).to.be.equal(1);

            const poolInfo = await hhJavFarming.poolInfo(0);

            await expect(poolInfo[0]).to.be.equal(basePair.target);
            await expect(poolInfo[1]).to.be.equal(allocPoint);
            await expect(poolInfo[2]).to.be.equal(blockNumber + BigInt(1));
            await expect(poolInfo[3]).to.be.equal(0);
        });

        it("Should revert when addPool - already exists", async () => {
            await expect(hhJavFarming.addPool(1, basePair.target)).to.be.revertedWith(
                "JavFarming: Duplicate pool",
            );
        });

        it("Should addPool with startBlock > blockNumber", async () => {
            await hhJavFarming.addAllowedPair(erc20Token2.target);

            const blockNumber = BigInt(await ethers.provider.getBlockNumber());
            const startBlock = blockNumber + BigInt(50);

            const allocPoint = ethers.parseEther("2");

            await hhJavFarming.setStartBlock(startBlock);
            await hhJavFarming.addPool(allocPoint, pair2.target);

            await expect(await hhJavFarming.getPoolLength()).to.be.equal(2);

            const poolInfo = await hhJavFarming.poolInfo(1);

            await expect(poolInfo[0]).to.be.equal(pair2.target);
            await expect(poolInfo[1]).to.be.equal(allocPoint);
            await expect(poolInfo[2]).to.be.equal(startBlock);
            await expect(poolInfo[3]).to.be.equal(0);
        });

        it("Should revert when setlastRewardBlock - admin error", async () => {
            await expect(
                hhJavFarming.connect(addr1).setlastRewardBlock(0, 1, 1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setlastRewardBlock", async () => {
            const pid = 1;
            const lastRewardBlock = BigInt(await ethers.provider.getBlockNumber());
            const accRewardPerShare = ethers.parseEther("1");

            await hhJavFarming.setlastRewardBlock(pid, lastRewardBlock, accRewardPerShare);

            const poolInfo = await hhJavFarming.poolInfo(pid);

            await expect(poolInfo[2]).to.be.equal(lastRewardBlock);
            await expect(poolInfo[3]).to.be.equal(accRewardPerShare);
        });

        it("Should getPoolLength", async () => {
            await expect(await hhJavFarming.getPoolLength()).to.be.equal(2);
        });

        it("Should revert when setAllocationPoint", async () => {
            await expect(hhJavFarming.connect(addr1).setAllocationPoint(1, 123)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should setAllocationPoint", async () => {
            const amount = ethers.parseEther("15");
            const pid = 1;

            await hhJavFarming.setAllocationPoint(pid, amount);

            const poolInfo = await hhJavFarming.poolInfo(pid);

            await expect(poolInfo[1]).to.be.equal(amount);
        });

        it("Should speedStake", async () => {
            const amount = ethers.parseEther("15");
            const pid = 0;
            const block = await ethers.provider.getBlock("latest");
            const deadlineTimestamp = BigInt(block.timestamp) + BigInt(10000000);

            await erc20Token.mint(addr1.address, amount);
            await erc20Token.connect(addr1).approve(hhJavFarming.target, amount);

            await hhJavFarming
                .connect(addr1)
                .speedStake(pid, 0, amount, 0, 0, 0, deadlineTimestamp);

            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);

            await expect(userInfo[0]).to.be.equal(userInfo[0]);
            await expect(userInfo[1]).to.be.equal(userInfo[1]);
            await expect(userInfo[2]).to.be.equal(0);
            await expect(userInfo[3]).to.be.equal(0);
        });

        it("Should speedStake with diff pool", async () => {
            const amount = ethers.parseEther("15");
            const pid = 1;
            const block = await ethers.provider.getBlock("latest");
            const deadlineTimestamp = BigInt(block.timestamp) + BigInt(10000000);

            await erc20Token.mint(addr2.address, amount);
            await erc20Token.connect(addr2).approve(hhJavFarming.target, amount);

            await hhJavFarming
                .connect(addr2)
                .speedStake(pid, 0, amount, 0, 0, 0, deadlineTimestamp);

            const userInfo = await hhJavFarming.userInfo(pid, addr2.address);

            await expect(userInfo[0]).to.be.equal(userInfo[0]);
            await expect(userInfo[1]).to.be.equal(userInfo[1]);
            await expect(userInfo[2]).to.be.equal(userInfo[1]);
            await expect(userInfo[3]).to.be.equal(0);
        });

        it("Should get pendingReward = 0, block = lastRewardBlock", async () => {
            const pid = 0;

            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);
            const poolInfo = await hhJavFarming.poolInfo(pid);
            const accRewardPerShare = poolInfo[3];
            const blockNumber = BigInt((await ethers.provider.getBlockNumber()) + 2);
            await hhJavFarming.setlastRewardBlock(pid, blockNumber, poolInfo[3]);

            const pendingReward =
                (userInfo[1] * accRewardPerShare) / ethers.parseEther("1") - userInfo[2];

            await expect(await hhJavFarming.pendingReward(pid, addr1.address)).to.be.equal(
                pendingReward,
            );
        });

        it("Should get pendingReward, block > lastRewardBlock", async () => {
            const pid = 0;
            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);
            const poolInfo = await hhJavFarming.poolInfo(pid);

            await helpers.mine(10);

            const blockNumber = await ethers.provider.getBlockNumber();

            const lpSupply = await basePair.balanceOf(hhJavFarming.target);
            const multiplier = await hhJavFarming.getMultiplier(poolInfo[2], blockNumber);
            const totalAllocPoint = await hhJavFarming.totalAllocPoint();
            const reward = (multiplier * BigInt(poolInfo[1])) / totalAllocPoint;

            const accRewardPerShare =
                BigInt(poolInfo[3]) + (reward * ethers.parseEther("1")) / lpSupply;

            const pendingReward =
                (userInfo[1] * accRewardPerShare) / ethers.parseEther("1") - userInfo[2];

            await expect(await hhJavFarming.pendingReward(pid, addr1.address)).to.be.equal(
                pendingReward,
            );
        });

        it("Should get pendingRewardTotal - 1 deposit", async () => {
            await expect(await hhJavFarming.pendingRewardTotal(addr1.address)).to.be.equal(
                await hhJavFarming.pendingReward(0, addr1.address),
            );
        });

        it("Should revert when harvest - poolError", async () => {
            await expect(hhJavFarming.connect(addr1).harvest(2)).to.be.revertedWith(poolError);
        });

        it("Should harvest", async () => {
            const pid = 0;
            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFarming.target);
            const userInfoBefore = await hhJavFarming.userInfo(pid, addr1.address);

            await hhJavFarming.connect(addr1).harvest(pid);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFarming.target);
            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);
            const pendingRewards = userInfo[3] - userInfoBefore[3];

            await expect(userInfo[3]).to.be.equal(userInfoBefore[3] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(contractBalanceBefore - pendingRewards);
            await expect(await hhJavFarming.pendingReward(pid, addr1.address)).to.be.equal(0);
        });

        it("Should harvestAll", async () => {
            const pid = 0;
            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFarming.target);
            const userInfoBefore = await hhJavFarming.userInfo(pid, addr1.address);

            await helpers.mine(10);
            await hhJavFarming.connect(addr1).harvestAll();

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFarming.target);
            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);
            const pendingRewards = userInfo[3] - userInfoBefore[3];

            await expect(userInfo[3]).to.be.equal(userInfoBefore[3] + pendingRewards);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingRewards);
            await expect(contractBalance).to.be.equal(contractBalanceBefore - pendingRewards);
            await expect(await hhJavFarming.pendingReward(pid, addr1.address)).to.be.equal(0);
        });

        it("Should revert when withdraw - poolError", async () => {
            await expect(hhJavFarming.connect(addr1).withdraw(3)).to.be.revertedWith(poolError);
        });

        it("Should  withdraw ", async () => {
            const pid = 0;
            await helpers.mine(50);

            const userBalanceBefore = await erc20Token.balanceOf(addr1.address);
            const contractBalanceBefore = await erc20Token.balanceOf(hhJavFarming.target);
            const userLpBalanceBefore = await basePair.balanceOf(addr1.address);
            const contractLpBalanceBefore = await basePair.balanceOf(hhJavFarming.target);
            const userInfoBefore = await hhJavFarming.userInfo(pid, addr1.address);
            const withdrawAmount = userInfoBefore[1];

            await hhJavFarming.connect(addr1).withdraw(pid);

            const userBalance = await erc20Token.balanceOf(addr1.address);
            const contractBalance = await erc20Token.balanceOf(hhJavFarming.target);
            const userLpBalance = await basePair.balanceOf(addr1.address);
            const contractLpBalance = await basePair.balanceOf(hhJavFarming.target);
            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);

            const pendingAmount = userInfo[3] - userInfoBefore[3];

            await expect(userInfo[0]).to.be.equal(0);
            await expect(userInfo[1]).to.be.equal(0);
            await expect(userInfo[2]).to.be.equal(0);
            await expect(userBalance).to.be.equal(userBalanceBefore + pendingAmount);
            await expect(contractBalance).to.be.equal(contractBalanceBefore - pendingAmount);
            await expect(userLpBalance).to.be.equal(userLpBalanceBefore + withdrawAmount);
            await expect(contractLpBalance).to.be.equal(contractLpBalanceBefore - withdrawAmount);

            await expect(await hhJavFarming.pendingReward(pid, addr1.address)).to.be.equal(0);
        });

        it("Should  deposit lp tokens ", async () => {
            const pid = 0;
            const amount = ethers.parseEther("5");

            const userLpBalanceBefore = await basePair.balanceOf(addr1.address);
            const contractLpBalanceBefore = await basePair.balanceOf(hhJavFarming.target);

            await basePair.connect(addr1).approve(hhJavFarming.target, amount);
            await hhJavFarming.connect(addr1).deposit(pid, amount);

            const userLpBalance = await basePair.balanceOf(addr1.address);
            const contractLpBalance = await basePair.balanceOf(hhJavFarming.target);
            const userInfo = await hhJavFarming.userInfo(pid, addr1.address);

            await expect(userInfo[1]).to.be.equal(amount);
            await expect(userLpBalance).to.be.equal(userLpBalanceBefore - amount);
            await expect(contractLpBalance).to.be.equal(contractLpBalanceBefore + amount);
        });
    });
});
