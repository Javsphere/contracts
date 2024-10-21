const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const { ADMIN_ERROR, MAX_UINT256 } = require("../common/constanst");
const { deployTokenFixture, deployInfinityPassFixture } = require("../common/mocks");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("BaseMigrator contract", () => {
    let hhBaseMigrator;
    let owner;
    let signer;
    let addr2;
    let addr3;
    let erc20Token;
    let vesting;
    let vestingFreezer;
    let infinityPass;
    let freezer;
    let staking;
    let AbiCoder;

    async function deployTokenVesting(tokenAddress) {
        const tokenVestingFactory = await ethers.getContractFactory("TokenVesting");
        [owner, ...addrs] = await ethers.getSigners();
        const vesting = await upgrades.deployProxy(tokenVestingFactory, [tokenAddress], {
            initializer: "initialize",
        });
        await vesting.waitForDeployment();
        return vesting;
    }

    async function deployTokenVestingFreezer() {
        const tokenVestingFreezerFactory = await ethers.getContractFactory("TokenVestingFreezer");
        [owner, ...addrs] = await ethers.getSigners();
        const vestingFreezer = await upgrades.deployProxy(
            tokenVestingFreezerFactory,
            ["0x0000000000000000000000000000000000000000"],
            {
                initializer: "initialize",
            },
        );
        await vestingFreezer.waitForDeployment();
        return vestingFreezer;
    }

    async function deployFreezer(vestingFreezerAddress, infinityPassAddress) {
        const freezerFactory = await ethers.getContractFactory("JavFreezer");
        [owner, ...addrs] = await ethers.getSigners();
        const freezer = await upgrades.deployProxy(
            freezerFactory,
            [
                ethers.parseEther("0.05"),
                864000,
                vestingFreezerAddress,
                5,
                infinityPassAddress,
                "0x0000000000000000000000000000000000000000",
            ],
            {
                initializer: "initialize",
            },
        );
        await freezer.waitForDeployment();
        return freezer;
    }

    async function deployStaking(infinityPassAddress) {
        const stakingFactory = await ethers.getContractFactory("JavStakeX");
        [owner, ...addrs] = await ethers.getSigners();
        const staking = await upgrades.deployProxy(
            stakingFactory,
            [
                ethers.parseEther("0.05"),
                864000,
                "0x0000000000000000000000000000000000000000",
                5,
                infinityPassAddress,
                "0x0000000000000000000000000000000000000000",
            ],
            {
                initializer: "initialize",
            },
        );
        await staking.waitForDeployment();
        return staking;
    }

    async function deployTokenVestingWrapper() {
        return deployTokenVesting(erc20Token.target);
    }

    async function deployFreezerWrapper() {
        return deployFreezer(vestingFreezer.target, infinityPass.target);
    }

    async function deployStakingWrapper() {
        return deployStaking(infinityPass.target);
    }

    before(async () => {
        const baseMigrator = await ethers.getContractFactory("BaseMigrator");
        [owner, signer, addr2, addr3, ...addrs] = await ethers.getSigners();

        erc20Token = await helpers.loadFixture(deployTokenFixture);
        vesting = await helpers.loadFixture(deployTokenVestingWrapper);
        vestingFreezer = await helpers.loadFixture(deployTokenVestingFreezer);
        infinityPass = await helpers.loadFixture(deployInfinityPassFixture);
        freezer = await helpers.loadFixture(deployFreezerWrapper);
        staking = await helpers.loadFixture(deployStakingWrapper);

        hhBaseMigrator = await upgrades.deployProxy(
            baseMigrator,
            [
                erc20Token.target, // _tokenAddress,
                vesting.target, // _vestingAddress
                vestingFreezer.target, // _vestingFreezerAddress
                staking.target, // _stakingAddress
                freezer.target, // _freezerAddress
                infinityPass.target, // _infinityPass
                signer.address, // _signerAddress
            ],
            {
                initializer: "initialize",
            },
        );

        AbiCoder = new ethers.AbiCoder();
    });

    describe("Deployment", () => {
        it("Should set the right deployment params", async () => {
            await expect(await hhBaseMigrator.token()).to.equal(erc20Token.target);
            await expect(await hhBaseMigrator.vestingAddress()).to.equal(vesting.target);
            await expect(await hhBaseMigrator.vestingFreezerAddress()).to.equal(
                vestingFreezer.target,
            );
            await expect(await hhBaseMigrator.stakingAddress()).to.equal(staking.target);
            await expect(await hhBaseMigrator.freezerAddress()).to.equal(freezer.target);
            await expect(await hhBaseMigrator.infinityPass()).to.equal(infinityPass.target);
            await expect(await hhBaseMigrator.signerAddress()).to.equal(signer.address);
        });

        it("Configurate contracts", async () => {
            await vesting.addAllowedAddress(hhBaseMigrator.target);

            await vestingFreezer.addAllowedAddress(hhBaseMigrator.target);
            await vestingFreezer.setFreezerAddress(freezer.target);

            await staking.setMigratorAddress(hhBaseMigrator.target);
            await staking.addPool(
                erc20Token.target,
                erc20Token.target,
                await ethers.provider.getBlockNumber(),
                ethers.parseEther("0.00"),
                ethers.parseEther("1"),
                {
                    depositFee: 1 * 1e2,
                    withdrawFee: 1 * 1e2,
                    claimFee: 0 * 1e2,
                },
            );

            await freezer.setMigratorAddress(hhBaseMigrator.target);
            await freezer.addPool(
                erc20Token.target,
                erc20Token.target,
                await ethers.provider.getBlockNumber(),
                ethers.parseEther("0.01"),
                {
                    depositFee: 1 * 1e2,
                    withdrawFee: 1 * 1e2,
                    claimFee: 1 * 1e2,
                },
            );
            await freezer.setLockPeriod(0, 120);

            await infinityPass.setAdminAddress(hhBaseMigrator.target);
        });
    });

    describe("Transactions", () => {
        it("Should makeMigration - 0 data", async () => {
            const migrationInfo = {
                user: addr2.address,
                tokenAmount: 0,
                stakingAmount: 0,
                infinityPassTokenId: 0,
                infinityPassUri: "",
                vestingSchedules: [],
                vestingFreezerSchedules: [],
                freezerDeposits: [],
            };

            const AbiCoder = new ethers.AbiCoder();
            const migrationData = AbiCoder.encode(
                [
                    "(address user,uint256 tokenAmount,uint256 stakingAmount,uint256 infinityPassTokenId,string infinityPassUri,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingSchedules,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingFreezerSchedules,(uint256,uint256,uint256,uint256,uint256,uint256,bool)[] freezerDeposits)",
                ],
                [migrationInfo],
            );

            const messageHash = ethers.keccak256(migrationData);
            const signature = await signer.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, migrationData]);

            await hhBaseMigrator.connect(addr2).makeMigration(signedData);

            await expect(await erc20Token.balanceOf(vesting.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(0);
            await expect(await infinityPass.balanceOf(addr2.address)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(0);
        });

        it("Should revert when makeMigration - AlreadyMigrated", async () => {
            const migrationInfo = {
                user: addr2.address,
                tokenAmount: 0,
                stakingAmount: 0,
                infinityPassTokenId: 0,
                infinityPassUri: "",
                vestingSchedules: [],
                vestingFreezerSchedules: [],
                freezerDeposits: [],
            };

            const AbiCoder = new ethers.AbiCoder();
            const migrationData = AbiCoder.encode(
                [
                    "(address user,uint256 tokenAmount,uint256 stakingAmount,uint256 infinityPassTokenId,string infinityPassUri,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingSchedules,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingFreezerSchedules,(uint256,uint256,uint256,uint256,uint256,uint256,bool)[] freezerDeposits)",
                ],
                [migrationInfo],
            );

            const messageHash = ethers.keccak256(migrationData);
            const signature = await signer.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, migrationData]);

            await expect(
                hhBaseMigrator.connect(addr2).makeMigration(signedData),
            ).to.be.revertedWithCustomError(hhBaseMigrator, "AlreadyMigrated");
        });

        it("Should migrateFunds - vesting", async () => {
            const beneficiary = addr2.address;
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("1");
            const vestingType = 1;
            const lockId = 1;

            const migrationInfo = {
                user: addr2.address,
                tokenAmount: 0,
                stakingAmount: 0,
                infinityPassTokenId: 0,
                infinityPassUri: "",
                vestingSchedules: [
                    {
                        beneficiary: beneficiary,
                        start: start,
                        cliff: cliff,
                        duration: duration,
                        slicePeriodSeconds: slicePeriodSeconds,
                        revocable: revocable,
                        amount: amount,
                        vestingType: vestingType,
                        lockId: lockId,
                    },
                ],
                vestingFreezerSchedules: [],
                freezerDeposits: [],
            };

            const migrationData = AbiCoder.encode(
                [
                    "(address user,uint256 tokenAmount,uint256 stakingAmount,uint256 infinityPassTokenId,string infinityPassUri,(address beneficiary,uint128 start,uint128 cliff,uint128 duration,uint128 slicePeriodSeconds,bool revocable,uint128 amount,uint8 vestingType,uint8 lockId)[] vestingSchedules,(address beneficiary,uint128 start,uint128 cliff,uint128 duration,uint128 slicePeriodSeconds,bool revocable,uint128 amount,uint8 vestingType,uint8 lockId)[] vestingFreezerSchedules,(uint256,uint256,uint256,uint256,uint256,uint256,bool)[] freezerDeposits)",
                ],
                [migrationInfo],
            );

            const messageHash = ethers.keccak256(migrationData);
            const signature = await signer.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, migrationData]);

            await erc20Token.mint(hhBaseMigrator.target, amount);

            await hhBaseMigrator.connect(addr2).makeMigration(signedData);

            const vestingScheduleForHolder = await vesting.getLastVestingScheduleForHolder(
                beneficiary,
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

            await expect(await vesting.vestingSchedulesTotalAmount()).to.be.equal(amount);

            await expect(await erc20Token.balanceOf(vesting.target)).to.be.equal(amount);
            await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(0);
            await expect(await infinityPass.balanceOf(addr2.address)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(hhBaseMigrator.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(0);
        });

        it("Should migrateFunds - vesting freezer", async () => {
            const vestingAmount = await erc20Token.balanceOf(vesting.target);

            const beneficiary = addr2.address;
            const start = await time.latest();
            const cliff = 2;
            const duration = 3;
            const slicePeriodSeconds = 1;
            const revocable = true;
            const amount = ethers.parseEther("2");
            const vestingType = 1;
            const lockId = 1;

            const migrationInfo = {
                user: addr2.address,
                tokenAmount: 0,
                stakingAmount: 0,
                infinityPassTokenId: 0,
                infinityPassUri: "",
                vestingSchedules: [],
                vestingFreezerSchedules: [
                    {
                        beneficiary: beneficiary,
                        start: start,
                        cliff: cliff,
                        duration: duration,
                        slicePeriodSeconds: slicePeriodSeconds,
                        revocable: revocable,
                        amount: amount,
                        vestingType: vestingType,
                        lockId: lockId,
                    },
                ],
                freezerDeposits: [],
            };

            const migrationData = AbiCoder.encode(
                [
                    "(address user,uint256 tokenAmount,uint256 stakingAmount,uint256 infinityPassTokenId,string infinityPassUri,(address beneficiary,uint128 start,uint128 cliff,uint128 duration,uint128 slicePeriodSeconds,bool revocable,uint128 amount,uint8 vestingType,uint8 lockId)[] vestingSchedules,(address beneficiary,uint128 start,uint128 cliff,uint128 duration,uint128 slicePeriodSeconds,bool revocable,uint128 amount,uint8 vestingType,uint8 lockId)[] vestingFreezerSchedules,(uint256,uint256,uint256,uint256,uint256,uint256,bool)[] freezerDeposits)",
                ],
                [migrationInfo],
            );

            const messageHash = ethers.keccak256(migrationData);
            const signature = await signer.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, migrationData]);

            await erc20Token.mint(hhBaseMigrator.target, amount);

            await hhBaseMigrator.connect(addr2).makeMigration(signedData);

            const vestingScheduleForHolder = await vestingFreezer.getLastVestingScheduleForHolder(
                beneficiary,
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

            await expect(await erc20Token.balanceOf(vesting.target)).to.be.equal(vestingAmount);
            await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(amount);
            await expect(await infinityPass.balanceOf(addr2.address)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(hhBaseMigrator.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(0);
        });

        // it("Should migrateFunds - staking", async () => {
        //     const lockAmount = await tokenLock.tokenAmount(addr2.address);
        //     const stakeAmount = ethers.parseEther("2");
        //     await erc20Token.mint(addr2.address, stakeAmount);
        //     await erc20Token.connect(addr2).approve(staking.target, stakeAmount);
        //
        //     await staking.connect(addr2).stake(0, stakeAmount);
        //     const userInfoBefore = await staking.userInfo(0, addr2.address);
        //     const shares = userInfoBefore.shares;
        //     await erc20Token.mint(staking.target, ethers.parseEther("1"));
        //     const stakingBalance = await erc20Token.balanceOf(staking.target);
        //
        //     await erc20Token.connect(addr2).approve(tokenLock.target, MAX_UINT256);
        //     await hhBaseMigrator.connect(addr2).migrateFunds(0);
        //
        //     const poolInfo = await staking.poolInfo(0);
        //     const userInfo = await staking.userInfo(0, addr2.address);
        //
        //     const claimAmount = userInfo.totalClaims;
        //
        //     await expect(poolInfo.totalShares).to.be.equal(0);
        //     await expect(poolInfo.rewardsPerShare).to.be.equal(0);
        //     await expect(userInfo.shares).to.be.equal(0);
        //     await expect(userInfo.blockRewardDebt).to.be.equal(0);
        //     await expect(userInfo.productsRewardDebt).to.be.equal(0);
        //
        //     await expect(await staking.pendingReward(0, addr2.address)).to.be.equal(0);
        //
        //     await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(
        //         stakingBalance - shares - claimAmount,
        //     );
        //     await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(0);
        //     await expect(await tokenLock.tokenAmount(addr2.address)).to.be.equal(
        //         claimAmount + lockAmount,
        //     );
        // });
        //
        // it("Should migrateFunds - freezer", async () => {
        //     const lockAmount = await tokenLock.tokenAmount(addr2.address);
        //     const amount = ethers.parseEther("1");
        //
        //     await erc20Token.mint(addr2.address, amount);
        //     await erc20Token.connect(addr2).approve(freezer.target, amount);
        //
        //     await freezer.connect(addr2).deposit(0, 0, amount);
        //
        //     await erc20Token.connect(addr2).approve(tokenLock.target, MAX_UINT256);
        //     await hhBaseMigrator.connect(addr2).migrateFunds(0);
        //
        //     const poolInfo = await freezer.poolInfo(0);
        //     const userInfo = await freezer.userInfo(addr2.address, 0);
        //     const claimAmount = userInfo.totalClaim;
        //
        //     await expect(userInfo.totalDepositTokens).to.be.equal(0);
        //     await expect(poolInfo.totalShares).to.be.equal(0);
        //
        //     await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(0);
        //     await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(0);
        //     await expect(await tokenLock.tokenAmount(addr2.address)).to.be.equal(
        //         claimAmount + lockAmount,
        //     );
        // });

        it("Should makeMigration - infinity pass", async () => {
            const vestingAmount = await erc20Token.balanceOf(vesting.target);
            const freezerAmount = await erc20Token.balanceOf(freezer.target);

            const migrationInfo = {
                user: addr2.address,
                tokenAmount: 0,
                stakingAmount: 0,
                infinityPassTokenId: 13,
                infinityPassUri: "test",
                vestingSchedules: [],
                vestingFreezerSchedules: [],
                freezerDeposits: [],
            };

            const migrationData = AbiCoder.encode(
                [
                    "(address user,uint256 tokenAmount,uint256 stakingAmount,uint256 infinityPassTokenId,string infinityPassUri,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingSchedules,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingFreezerSchedules,(uint256,uint256,uint256,uint256,uint256,uint256,bool)[] freezerDeposits)",
                ],
                [migrationInfo],
            );

            const messageHash = ethers.keccak256(migrationData);
            const signature = await signer.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, migrationData]);

            await hhBaseMigrator.connect(addr2).makeMigration(signedData);

            await expect(await erc20Token.balanceOf(vesting.target)).to.be.equal(vestingAmount);
            await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(freezerAmount);
            await expect(await infinityPass.balanceOf(addr2.address)).to.be.equal(1);
            await expect(await infinityPass.ownerOf(13)).to.be.equal(addr2.address);
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(hhBaseMigrator.target)).to.be.equal(0);
        });

        it("Should makeMigration - wallet balance", async () => {
            const vestingAmount = await erc20Token.balanceOf(vesting.target);
            const freezerAmount = await erc20Token.balanceOf(freezer.target);
            const amount = ethers.parseEther("5");
            const migrationInfo = {
                user: addr2.address,
                tokenAmount: amount,
                stakingAmount: 0,
                infinityPassTokenId: 0,
                infinityPassUri: "",
                vestingSchedules: [],
                vestingFreezerSchedules: [],
                freezerDeposits: [],
            };

            await erc20Token.mint(hhBaseMigrator.target, amount);
            const migrationData = AbiCoder.encode(
                [
                    "(address user,uint256 tokenAmount,uint256 stakingAmount,uint256 infinityPassTokenId,string infinityPassUri,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingSchedules,(address,uint128,uint128,uint128,uint128,bool,uint128,uint8,uint8)[] vestingFreezerSchedules,(uint256,uint256,uint256,uint256,uint256,uint256,bool)[] freezerDeposits)",
                ],
                [migrationInfo],
            );

            const messageHash = ethers.keccak256(migrationData);
            const signature = await signer.signMessage(ethers.getBytes(messageHash));
            const signedData = ethers.concat([signature, migrationData]);

            await hhBaseMigrator.connect(addr2).makeMigration(signedData);

            await expect(await erc20Token.balanceOf(vesting.target)).to.be.equal(vestingAmount);
            await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(freezerAmount);
            await expect(await infinityPass.balanceOf(addr2.address)).to.be.equal(1);
            await expect(await erc20Token.balanceOf(hhBaseMigrator.target)).to.be.equal(0);
            await expect(await erc20Token.balanceOf(addr2.address)).to.be.equal(amount);
        });
        //
        // it("Should migrateFunds - all", async () => {
        //     const user = addr3.address;
        //     const vestingAmount = ethers.parseEther("5");
        //     const vestingFreezerAmount = ethers.parseEther("6");
        //     const stakeAmount = ethers.parseEther("2");
        //     const freezerAmount = ethers.parseEther("3");
        //
        //     await erc20Token.mint(vesting.target, vestingAmount);
        //
        //     await vesting.createVestingSchedule(
        //         user,
        //         await time.latest(),
        //         2,
        //         3500000,
        //         1,
        //         true,
        //         vestingAmount,
        //         0,
        //         0,
        //     );
        //
        //     await erc20Token.mint(freezer.target, vestingFreezerAmount);
        //     await vestingFreezer.createVestingSchedule(
        //         user,
        //         await time.latest(),
        //         2,
        //         3500000,
        //         1,
        //         true,
        //         vestingFreezerAmount,
        //         1,
        //         0,
        //     );
        //
        //     await erc20Token.mint(addr3.address, stakeAmount);
        //     await erc20Token.connect(addr3).approve(staking.target, stakeAmount);
        //     await staking.connect(addr3).stake(0, stakeAmount);
        //     const stakingBalance = await erc20Token.balanceOf(staking.target);
        //     const userInfoBefore = await staking.userInfo(0, addr3.address);
        //     const shares = userInfoBefore.shares;
        //
        //     await erc20Token.mint(addr3.address, freezerAmount);
        //     await erc20Token.connect(addr3).approve(freezer.target, freezerAmount);
        //
        //     await freezer.connect(addr3).deposit(0, 0, freezerAmount);
        //
        //     await infinityPass.makeMigration(addr3.address, 1, "test");
        //
        //     await erc20Token.connect(addr3).approve(tokenLock.target, MAX_UINT256);
        //     await infinityPass.connect(addr3).approve(hhBaseMigrator.target, 1);
        //     await hhBaseMigrator.connect(addr3).migrateFunds(1);
        //
        //     const vestingScheduleForHolder = await vesting.getLastVestingScheduleForHolder(user);
        //     const vestingReleased = vestingScheduleForHolder.released;
        //
        //     const vestingFreezerScheduleForHolder =
        //         await vestingFreezer.getLastVestingScheduleForHolder(user);
        //     const vestingFreezerReleased = vestingFreezerScheduleForHolder.released;
        //
        //     const userInfoStaking = await staking.userInfo(0, addr3.address);
        //     const claimAmountStaking = userInfoStaking.totalClaims;
        //
        //     const userInfoFreezer = await freezer.userInfo(addr3.address, 0);
        //     const claimAmountFreezer = userInfoFreezer.totalClaim;
        //
        //     await expect(vestingScheduleForHolder.revoked).to.be.equal(true);
        //     await expect(await erc20Token.balanceOf(vesting.target)).to.be.equal(0);
        //
        //     await expect(vestingFreezerScheduleForHolder.revoked).to.be.equal(true);
        //     await expect(await erc20Token.balanceOf(vestingFreezer.target)).to.be.equal(0);
        //
        //     await expect(await erc20Token.balanceOf(staking.target)).to.be.equal(
        //         stakingBalance - shares - claimAmountStaking,
        //     );
        //
        //     await expect(await erc20Token.balanceOf(freezer.target)).to.be.equal(0);
        //
        //     await expect(await erc20Token.balanceOf(addr3.address)).to.be.equal(0);
        //
        //     await expect(await infinityPass.balanceOf(addr3.address)).to.be.equal(0);
        //
        //     await expect(await tokenLock.tokenAmount(addr3.address)).to.be.equal(
        //         vestingReleased + vestingFreezerReleased + claimAmountStaking + claimAmountFreezer,
        //     );
        // });
    });
});
