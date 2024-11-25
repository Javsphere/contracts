const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const { deployTokenFixture, deployInfinityPassFixture } = require("../common/mocks");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADMIN_ERROR } = require("../common/constanst");

describe("Vote contract", () => {
    let hhVote;
    let owner;
    let addr2;
    let addr3;
    let erc20Token;
    let vesting;
    let infinityPass;
    let freezer;
    let staking;

    async function deployTokenVesting(tokenAddress) {
        const tokenVestingFactory = await ethers.getContractFactory("TokenVesting");
        [owner, ...addrs] = await ethers.getSigners();
        const vesting = await upgrades.deployProxy(tokenVestingFactory, [tokenAddress], {
            initializer: "initialize",
        });
        await vesting.waitForDeployment();
        return vesting;
    }

    async function deployFreezer(vestingFreezerAddress, infinityPassAddress) {
        const freezerFactory = await ethers.getContractFactory(
            "contracts/dmc/JavFreezer.sol:JavFreezer",
        );
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
        const stakingFactory = await ethers.getContractFactory(
            "contracts/dmc/JavStakeX.sol:JavStakeX",
        );
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
        return deployFreezer(infinityPass.target, infinityPass.target);
    }

    async function deployStakingWrapper() {
        return deployStaking(infinityPass.target);
    }

    before(async () => {
        const vote = await ethers.getContractFactory("Vote");
        [owner, addr2, addr3, ...addrs] = await ethers.getSigners();

        erc20Token = await helpers.loadFixture(deployTokenFixture);
        vesting = await helpers.loadFixture(deployTokenVestingWrapper);
        infinityPass = await helpers.loadFixture(deployInfinityPassFixture);
        freezer = await helpers.loadFixture(deployFreezerWrapper);
        staking = await helpers.loadFixture(deployStakingWrapper);

        hhVote = await upgrades.deployProxy(
            vote,
            [
                addr2.address, // _adminAddress,
                vesting.target, // _vestingAddress
                staking.target, // _stakingAddress
                freezer.target, // _freezerAddress
                100, // stakingFactor
                200, // vestingFactor
                [0, 1], // _freezerIdsFactor
                [300, 400], // _freezerFactors
            ],
            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right deployment params", async () => {
            await expect(await hhVote.vestingAddress()).to.equal(vesting.target);
            await expect(await hhVote.stakingAddress()).to.equal(staking.target);
            await expect(await hhVote.freezerAddress()).to.equal(freezer.target);
            await expect(await hhVote.stakingFactor()).to.equal(100);
            await expect(await hhVote.vestingFactor()).to.equal(200);
            await expect(await hhVote.freezerFactor(0)).to.equal(300);
            await expect(await hhVote.freezerFactor(1)).to.equal(400);
        });

        it("Configurate contracts", async () => {
            await staking.addPool(
                erc20Token.target,
                erc20Token.target,
                await ethers.provider.getBlockNumber(),
                ethers.parseEther("0.00"),
                ethers.parseEther("1"),
                {
                    depositFee: 0 * 1e2,
                    withdrawFee: 1 * 1e2,
                    claimFee: 0 * 1e2,
                },
            );

            await freezer.addPool(
                erc20Token.target,
                erc20Token.target,
                await ethers.provider.getBlockNumber(),
                ethers.parseEther("0.01"),
                {
                    depositFee: 0 * 1e2,
                    withdrawFee: 1 * 1e2,
                    claimFee: 1 * 1e2,
                },
            );
            await freezer.setLockPeriod(0, 120);
            await freezer.setLockPeriod(1, 240);
        });
    });

    describe("Transactions", () => {
        it("Should revert when createProposal - only admin", async () => {
            await expect(hhVote.connect(addr3).createProposal(1, 1, "test")).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should get votingPower", async () => {
            const stakeAmount = ethers.parseEther("2");
            const vestingAmount = ethers.parseEther("3");
            const freezerAmount0 = ethers.parseEther("4");
            const freezerAmount1 = ethers.parseEther("5");
            await erc20Token.mint(addr2.address, stakeAmount + freezerAmount0 + freezerAmount1);
            await erc20Token.mint(vesting.target, vestingAmount);
            await erc20Token.connect(addr2).approve(staking.target, stakeAmount);
            await erc20Token
                .connect(addr2)
                .approve(freezer.target, freezerAmount0 + freezerAmount1);

            await staking.connect(addr2).stake(0, stakeAmount);

            await vesting.createVestingSchedule(
                addr2.address,
                await time.latest(),
                2,
                3500000,
                1,
                true,
                vestingAmount,
                0,
                0,
            );
            await freezer.connect(addr2).deposit(0, 0, freezerAmount0);
            await freezer.connect(addr2).deposit(0, 1, freezerAmount1);

            const stakingPower = (stakeAmount * BigInt(100)) / BigInt(100);
            const vestingPower = (vestingAmount * BigInt(200)) / BigInt(100);
            const freezerPower0 = (freezerAmount0 * BigInt(300)) / BigInt(100);
            const freezerPower1 = (freezerAmount1 * BigInt(400)) / BigInt(100);

            await expect(await hhVote.votingPower(addr2.address)).to.be.equal(
                stakingPower + vestingPower + freezerPower0 + freezerPower1,
            );
        });

        it("Should createProposal", async () => {
            const now = await time.latest();
            const startTime = now + 100;
            const endTime = now + 1000;
            const description = "hhtet";

            const id = await hhVote.proposalIndex();
            await hhVote.connect(addr2).createProposal(startTime, endTime, description);

            const proposal = await hhVote.proposals(id);
            await expect(proposal.proposer).to.be.equal(addr2.address);
            await expect(proposal.startTimestamp).to.be.equal(startTime);
            await expect(proposal.endTimestamp).to.be.equal(endTime);
            await expect(proposal.descriptionId).to.be.equal(description);
            await expect(proposal.isExecuted).to.be.equal(false);
            await expect(proposal.isApproved).to.be.equal(false);
            await expect(await hhVote.proposalIndex()).to.be.equal(id + BigInt(1));
        });

        it("Should revert when voteForProposal - InvalidVotePeriod -start time", async () => {
            const id = (await hhVote.proposalIndex()) - BigInt(1);
            await expect(
                hhVote.connect(addr2).voteForProposal(id, true),
            ).to.be.revertedWithCustomError(hhVote, "InvalidVotePeriod");
        });

        it("Should voteForProposal", async () => {
            await time.increase(100);
            await helpers.mine(1);

            const id = (await hhVote.proposalIndex()) - BigInt(1);
            const votingPower = await hhVote.votingPower(addr2.address);

            await hhVote.connect(addr2).voteForProposal(id, true);

            await expect(await hhVote.proposalWeight(id, true)).to.be.equal(votingPower);
            await expect(await hhVote.votedProposal(addr2.address, id)).to.be.equal(true);
            await expect(await hhVote.votedDirection(addr2.address, id)).to.be.equal(true);
        });

        it("Should revert when executeProposal - NotEnded ", async () => {
            const id = (await hhVote.proposalIndex()) - BigInt(1);
            await expect(hhVote.connect(addr2).executeProposal(id)).to.be.revertedWithCustomError(
                hhVote,
                "NotEnded",
            );
        });

        it("Should revert when voteForProposal - AlreadyVoted", async () => {
            const id = (await hhVote.proposalIndex()) - BigInt(1);
            await expect(
                hhVote.connect(addr2).voteForProposal(id, false),
            ).to.be.revertedWithCustomError(hhVote, "AlreadyVoted");
        });

        it("Should revert when voteForProposal - InvalidVotePeriod - end time", async () => {
            await time.increase(1000);
            await helpers.mine(1);
            const id = (await hhVote.proposalIndex()) - BigInt(1);
            await expect(hhVote.voteForProposal(id, true)).to.be.revertedWithCustomError(
                hhVote,
                "InvalidVotePeriod",
            );
        });

        it("Should executeProposal", async () => {
            const id = (await hhVote.proposalIndex()) - BigInt(1);

            await hhVote.connect(addr2).executeProposal(id);
            const proposal = await hhVote.proposals(id);

            await expect(proposal.isExecuted).to.be.equal(true);
            await expect(proposal.isApproved).to.be.equal(true);
        });

        it("Should revert when execute proposal - WrongIndex", async () => {
            const id = await hhVote.proposalIndex();
            await expect(hhVote.executeProposal(id)).to.be.revertedWithCustomError(
                hhVote,
                "WrongIndex",
            );
        });
    });
});
