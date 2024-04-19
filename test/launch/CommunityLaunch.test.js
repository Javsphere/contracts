const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployToken2Fixture,
    deployUniswapFixture,
    deployStateRelayerFixture,
} = require("../common/mocks");
const { ADMIN_ERROR } = require("../common/constanst");

describe("CommunityLaunch contract", () => {
    let hhCommunityLaunch;
    let owner;
    let addr1;
    let addr2;
    let bot;
    let admin;
    let freezerMock;
    let erc20Token;
    let erc20Token2;
    let erc20Token3;
    let stateRelayer;
    let wdfiToken;
    let uniswapFactory;
    let uniswapRouter;
    let uniswapPairContract;
    let basePair;
    let vestingMock;
    let saleActiveError;
    let startTokenPrice;
    let endTokenPrice;
    let tokensToSale;
    let amountWeth;
    let amount0;

    async function deployVestingFixture() {
        const tokenVestingFactory = await ethers.getContractFactory("TokenVestingFreezer");
        const freezerContractFactory = await ethers.getContractFactory("JavFreezerMock");
        const freezer = await freezerContractFactory.deploy();
        await freezer.waitForDeployment();

        const vestingMock = await upgrades.deployProxy(tokenVestingFactory, [freezer.target], {
            initializer: "initialize",
        });
        await vestingMock.waitForDeployment();
        return [vestingMock, freezer];
    }

    async function deployTokenFixture() {
        const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
        const erc20Token = await erc20ContractFactory.deploy("Mock3ERC20", "MOCK3");
        await erc20Token.waitForDeployment();
        return erc20Token;
    }

    before(async () => {
        const communityLaunch = await ethers.getContractFactory("CommunityLaunch");

        [owner, addr1, addr2, admin, bot, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        erc20Token3 = await deployTokenFixture();
        stateRelayer = await helpers.loadFixture(deployStateRelayerFixture);
        const vestingData = await deployVestingFixture();

        const data = await helpers.loadFixture(deployUniswapFixture);
        [wdfiToken, uniswapFactory, uniswapRouter, uniswapPairContract] = Object.values(data);
        [vestingMock, freezerMock] = vestingData;

        startTokenPrice = ethers.parseEther("1");
        endTokenPrice = ethers.parseEther("2");
        tokensToSale = ethers.parseEther("100");

        // create pairs
        await uniswapFactory.createPair(wdfiToken.target, erc20Token2.target);
        let allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        basePair = uniswapPairContract.attach(pairCreated);

        hhCommunityLaunch = await upgrades.deployProxy(
            communityLaunch,
            [
                tokensToSale,
                startTokenPrice,
                endTokenPrice,
                6,
                [ethers.parseEther("50")],
                {
                    tokenAddress: await erc20Token.getAddress(),
                    stateRelayer: stateRelayer.target,
                    botAddress: bot.address,
                    dusdAddress: await erc20Token2.getAddress(),
                    usdtAddress: await erc20Token3.getAddress(),
                    pairAddress: basePair.target,
                    vesting: vestingMock.target,
                    freezer: freezerMock.target,
                },
                {
                    cliff: 200,
                    duration: 300,
                    slicePeriodSeconds: 50,
                    vestingType: 0,
                    lockId: 0,
                },
            ],

            {
                initializer: "initialize",
            },
        );

        saleActiveError = "CommunityLaunch: contract is not available right now";

        // add liquidity
        amountWeth = ethers.parseEther("500");
        amount0 = ethers.parseEther("100");
        await wdfiToken.deposit({ value: amountWeth });
        await erc20Token2.mint(owner.address, amount0);

        await wdfiToken.approve(uniswapRouter.target, ethers.parseEther("100000"));
        await erc20Token2.approve(uniswapRouter.target, ethers.parseEther("100000"));

        await uniswapRouter.addLiquidity(
            erc20Token2.target,
            wdfiToken.target,
            amount0,
            amountWeth,
            1,
            1,
            owner.address,
            // wait time
            "999999999999999999999999999999",
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhCommunityLaunch.owner()).to.equal(owner.address);
        });

        it("Should set the right token address", async () => {
            await expect(await hhCommunityLaunch.token()).to.equal(erc20Token.target);
        });

        it("Should set the right vesting address", async () => {
            await expect(await hhCommunityLaunch.vestingAddress()).to.equal(vestingMock.target);
        });

        it("Should set the right freezerMock address", async () => {
            await expect(await hhCommunityLaunch.freezerAddress()).to.equal(freezerMock.target);
        });

        it("Should set the right dusd address", async () => {
            await expect(await hhCommunityLaunch.dusdAddress()).to.equal(erc20Token2.target);
        });

        it("Should set the right usdt address", async () => {
            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token3.target);
        });

        it("Should set the right pair address", async () => {
            await expect(await hhCommunityLaunch.pairAddress()).to.equal(basePair.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhCommunityLaunch.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right vestingParams", async () => {
            const vestingParams = await hhCommunityLaunch.vestingParams();
            await expect(vestingParams[0]).to.equal(200);
            await expect(vestingParams[1]).to.equal(300);
            await expect(vestingParams[2]).to.equal(50);
            await expect(vestingParams[3]).to.equal(0);
            await expect(vestingParams[4]).to.equal(0);
        });

        it("Should set the right isSaleActive flag", async () => {
            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(false);
        });

        it("Should set the right startTokenPrice", async () => {
            await expect(await hhCommunityLaunch.startTokenPrice()).to.equal(startTokenPrice);
        });

        it("Should set the right endTokenPrice", async () => {
            await expect(await hhCommunityLaunch.endTokenPrice()).to.equal(endTokenPrice);
        });

        it("Should set the right sectionsNumber", async () => {
            await expect(await hhCommunityLaunch.sectionsNumber()).to.equal(6);
        });

        it("Should set the right tokensToSale", async () => {
            await expect(await hhCommunityLaunch.tokensAmountByType(0)).to.equal(
                ethers.parseEther("50"),
            );
            await expect(await hhCommunityLaunch.tokensToSale()).to.equal(tokensToSale);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("120");

            await erc20Token.mint(hhCommunityLaunch.target, tokenAmounts);
            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.equal(
                tokenAmounts,
            );
        });

        it("Should addAllowedAddress", async () => {
            await vestingMock.addAllowedAddress(hhCommunityLaunch.target);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set the admin address", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setAdminAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhCommunityLaunch.setAdminAddress(admin.address);

            await expect(await hhCommunityLaunch.adminAddress()).to.equal(admin.address);
        });

        it("Should revert when setVestingParams", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setVestingParams({
                    start: 100,
                    cliff: 200,
                    duration: 300,
                    slicePeriodSeconds: 50,
                    vestingType: 0,
                    lockId: 0,
                }),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setVestingParams", async () => {
            await hhCommunityLaunch.setVestingParams({
                cliff: 200,
                duration: 300,
                slicePeriodSeconds: 50,
                vestingType: 0,
                lockId: 0,
            });

            const vestingParams = await hhCommunityLaunch.vestingParams();
            await expect(vestingParams[0]).to.equal(200);
            await expect(vestingParams[1]).to.equal(300);
            await expect(vestingParams[2]).to.equal(50);
            await expect(vestingParams[3]).to.equal(0);
            await expect(vestingParams[4]).to.equal(0);
        });

        it("Should revert when setVestingAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setVestingAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setVestingAddress", async () => {
            await hhCommunityLaunch.setVestingAddress(vestingMock.target);

            await expect(await hhCommunityLaunch.vestingAddress()).to.equal(vestingMock.target);
        });

        it("Should revert when setFreezerAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setFreezerAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setFreezerAddress", async () => {
            await hhCommunityLaunch.setFreezerAddress(freezerMock);

            await expect(await hhCommunityLaunch.freezerAddress()).to.equal(freezerMock.target);
        });

        it("Should revert when setUSDTAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setUSDTAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setUSDTAddress", async () => {
            await hhCommunityLaunch.setUSDTAddress(erc20Token3.target);

            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token3.target);
        });

        it("Should revert when setDUSDAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setDUSDAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setDUSDAddress", async () => {
            await hhCommunityLaunch.setDUSDAddress(erc20Token2.target);

            await expect(await hhCommunityLaunch.dusdAddress()).to.equal(erc20Token2.target);
        });

        it("Should revert when setPairAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setPairAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setPairAddress", async () => {
            await hhCommunityLaunch.setPairAddress(basePair.target);

            await expect(await hhCommunityLaunch.pairAddress()).to.equal(basePair.target);
        });

        it("Should revert when set setSaleActive", async () => {
            await expect(hhCommunityLaunch.connect(addr1).setSaleActive(true)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should revert when setBotAddress", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setBotAddress(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setBotAddress", async () => {
            await hhCommunityLaunch.setBotAddress(bot.address);

            await expect(await hhCommunityLaunch.botAddress()).to.equal(bot.address);
        });

        it("Should revert when stateRelayer", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setStateRelayer(admin.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should stateRelayer", async () => {
            await hhCommunityLaunch.setStateRelayer(stateRelayer.target);

            await expect(await hhCommunityLaunch.stateRelayer()).to.equal(stateRelayer.target);
        });

        it("Should set the setSaleActive", async () => {
            await hhCommunityLaunch.setSaleActive(true);

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(true);
        });

        it("Should revert when set the setStartTokenPrice", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setStartTokenPrice(ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setStartTokenPrice", async () => {
            await hhCommunityLaunch.setStartTokenPrice(startTokenPrice);

            await expect(await hhCommunityLaunch.startTokenPrice()).to.equal(startTokenPrice);
        });

        it("Should revert when set the endTokenPrice", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setEndTokenPrice(ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the endTokenPrice", async () => {
            await hhCommunityLaunch.setEndTokenPrice(endTokenPrice);

            await expect(await hhCommunityLaunch.endTokenPrice()).to.equal(endTokenPrice);
        });

        it("Should revert when set the setSectionsNumber", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setSectionsNumber(ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setSectionsNumber", async () => {
            await hhCommunityLaunch.setSectionsNumber(6);

            await expect(await hhCommunityLaunch.sectionsNumber()).to.equal(6);
        });

        it("Should revert when set the setTokensAmountByType", async () => {
            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .setTokensAmountByType([
                        ethers.parseEther("0.0005"),
                        ethers.parseEther("0.0005"),
                    ]),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setTokensAmountByType", async () => {
            await hhCommunityLaunch.setTokensAmountByType([ethers.parseEther("60")]);

            await expect(await hhCommunityLaunch.tokensAmountByType(0)).to.equal(
                ethers.parseEther("60"),
            );
        });

        it("Should revert when set the setTokensToSale", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setTokensToSale(ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setTokensToSale", async () => {
            tokensToSale = ethers.parseEther("120");
            await hhCommunityLaunch.setTokensToSale(tokensToSale);

            await expect(await hhCommunityLaunch.tokensToSale()).to.equal(tokensToSale);
        });

        it("Should revert when set the setMaxBagSize", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setMaxBagSize(ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setMaxBagSize", async () => {
            tokensToSale = ethers.parseEther("500");
            await hhCommunityLaunch.setMaxBagSize(tokensToSale);

            await expect(await hhCommunityLaunch.maxBagSize()).to.equal(tokensToSale);
        });

        it("Should revert when set the setTokenFactor", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setTokenFactor(1, [1, 2]),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setTokenFactor", async () => {
            await hhCommunityLaunch.setTokenFactor(0, [180, 140]);
            await hhCommunityLaunch.setTokenFactor(1, [200, 160]);
            await hhCommunityLaunch.setTokenFactor(2, [200, 110]);

            await expect(await hhCommunityLaunch.tokenFactor(0, 0)).to.equal(180);
            await expect(await hhCommunityLaunch.tokenFactor(0, 1)).to.equal(140);
        });

        it("Should getTokenAmountByUsd", async () => {
            const amount = ethers.parseEther("1");

            await expect(await hhCommunityLaunch.getTokenAmountByUsd(amount)).to.equal(amount);
        });

        it("Should getTokenFactorBonus", async () => {
            await expect(await hhCommunityLaunch.getTokenFactorBonus(0)).to.equal(
                await hhCommunityLaunch.tokenFactor(0, 0),
            );
        });

        it("Should getTokenAmountByUsd - next section", async () => {
            const usdAmount = ethers.parseEther("30");
            const tokenPerSection =
                (await hhCommunityLaunch.tokensToSale()) /
                (await hhCommunityLaunch.sectionsNumber());
            const sectionsNumber = await hhCommunityLaunch.sectionsNumber();
            const incPricePerSection =
                (endTokenPrice - startTokenPrice) / (sectionsNumber - BigInt(1));
            const section2Tokens = usdAmount - tokenPerSection;
            const amount =
                (section2Tokens * ethers.parseEther("1")) / (startTokenPrice + incPricePerSection);

            await expect(await hhCommunityLaunch.getTokenAmountByUsd(usdAmount)).to.be.equal(
                amount + tokenPerSection,
            );
        });

        it("Should get the right tokensBalance", async () => {
            await expect(await hhCommunityLaunch.tokensBalance()).to.equal(
                ethers.parseEther("120"),
            );
        });

        it("Should revert when buy with isSaleActive = false", async () => {
            await hhCommunityLaunch.setSaleActive(false);

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, erc20Token2.target, false, {
                    value: ethers.parseEther("1.0"),
                }),
            ).to.be.revertedWith(saleActiveError);

            await hhCommunityLaunch.setSaleActive(true);
        });

        it("Should buy jav tokens with usdt _isLongerVesting =  false", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("5");
            await erc20Token3.mint(addr1.address, usdtAmount);
            await erc20Token3.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);
            const tokensBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokenBeforeFreezer = await erc20Token.balanceOf(freezerMock.target);
            const tokensAmountByTypeBefore = await hhCommunityLaunch.tokensAmountByType(0);

            const amount = await hhCommunityLaunch.getTokenAmountByUsd(usdtAmount);

            await hhCommunityLaunch
                .connect(addr1)
                .buy(addr1.address, usdtAmount, erc20Token3.target, false, {
                    value: 0,
                });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            const vestingParams = await hhCommunityLaunch.vestingParams();

            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(await vestingScheduleForHolder.duration).to.be.equal(
                vestingParams.duration,
            );
            await expect(await vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                vestingParams.slicePeriodSeconds,
            );

            await expect(await erc20Token3.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                usdtAmount,
            );
            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokensBefore - amount,
            );
            await expect(await erc20Token.balanceOf(freezerMock.target)).to.be.equal(
                tokenBeforeFreezer + amount,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokensBefore - amount,
            );
            await expect(await hhCommunityLaunch.tokensAmountByType(0)).to.be.equal(
                tokensAmountByTypeBefore,
            );
        });

        it("Should buy jav tokens with usdt _isLongerVesting =  true", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("5");
            await erc20Token3.mint(addr1.address, usdtAmount);
            await erc20Token3.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);
            const tokensBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const usdtTokensBefore = await erc20Token3.balanceOf(hhCommunityLaunch.target);
            const tokenBeforeFreezer = await erc20Token.balanceOf(freezerMock.target);
            const tokensAmountByTypeBefore = await hhCommunityLaunch.tokensAmountByType(0);

            const amount = await hhCommunityLaunch.getTokenAmountByUsd(usdtAmount);

            const amountTotal =
                (amount * (await hhCommunityLaunch.getTokenFactorBonus(1))) / BigInt(100);

            await hhCommunityLaunch
                .connect(addr1)
                .buy(addr1.address, usdtAmount, erc20Token3.target, true, {
                    value: 0,
                });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            const vestingParams = await hhCommunityLaunch.vestingParams();

            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amountTotal);
            await expect(await vestingScheduleForHolder.duration).to.be.equal(
                vestingParams.duration * BigInt(2),
            );
            await expect(await vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                vestingParams.slicePeriodSeconds,
            );

            await expect(await erc20Token3.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                usdtTokensBefore + usdtAmount,
            );
            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokensBefore - amountTotal,
            );
            await expect(await erc20Token.balanceOf(freezerMock.target)).to.be.equal(
                tokenBeforeFreezer + amountTotal,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokensBefore - amountTotal,
            );
            await expect(await hhCommunityLaunch.tokensAmountByType(0)).to.be.equal(
                tokensAmountByTypeBefore,
            );
        });

        it("Should buy jav tokens with dusd _isLongerVesting =  false", async () => {
            await helpers.mine(10);

            const tokensBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokens2Before = await erc20Token2.balanceOf(hhCommunityLaunch.target);
            const dusdAmount = ethers.parseEther("5");
            await erc20Token2.mint(addr1.address, dusdAmount);
            await erc20Token2.connect(addr1).approve(hhCommunityLaunch.target, dusdAmount);
            const availableDUSDAmount = await hhCommunityLaunch.tokensAmountByType(0);

            await hhCommunityLaunch.updateDUSDPrice();

            const firstTokenBalance = BigInt(313643539540840000000000);
            const secondTokenBalance = BigInt(3988438984219900000000000);

            const dfiAmount = (dusdAmount * amountWeth) / amount0;

            const price = (ethers.parseEther("1") * firstTokenBalance) / secondTokenBalance;
            const usdAmount = (dfiAmount * price) / ethers.parseEther("1");
            const amount = await hhCommunityLaunch.getTokenAmountByUsd(usdAmount);

            await stateRelayer.updateDEXInfo(
                ["dUSDT-DFI"],
                [
                    {
                        primaryTokenPrice: ethers.parseEther("1"),
                        volume24H: 0,
                        totalLiquidity: 0,
                        APR: 0,
                        firstTokenBalance: firstTokenBalance,
                        secondTokenBalance: secondTokenBalance,
                        rewards: 0,
                        commissions: 0,
                    },
                ],
                0,
                0,
            );

            await hhCommunityLaunch
                .connect(addr1)
                .buy(addr1.address, dusdAmount, erc20Token2.target, false, {
                    value: 0,
                });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );

            const vestingParams = await hhCommunityLaunch.vestingParams();

            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amount);
            await expect(await vestingScheduleForHolder.duration).to.be.equal(
                vestingParams.duration,
            );
            await expect(await vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                vestingParams.slicePeriodSeconds,
            );

            await expect(await erc20Token2.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokens2Before + dusdAmount,
            );

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokensBefore - amount,
            );

            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokensBefore - amount,
            );
            await expect(await hhCommunityLaunch.tokensAmountByType(0)).to.be.equal(
                availableDUSDAmount - amount,
            );
        });

        it("Should buy jav tokens with dusd _isLongerVesting =  true", async () => {
            await helpers.mine(10);

            const tokensBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokens2Before = await erc20Token2.balanceOf(hhCommunityLaunch.target);
            const dusdAmount = ethers.parseEther("5");
            await erc20Token2.mint(addr1.address, dusdAmount);
            await erc20Token2.connect(addr1).approve(hhCommunityLaunch.target, dusdAmount);

            await hhCommunityLaunch.updateDUSDPrice();

            const firstTokenBalance = BigInt(313643539540840000000000);
            const secondTokenBalance = BigInt(3988438984219900000000000);

            const dfiAmount = (dusdAmount * amountWeth) / amount0;

            const price = (ethers.parseEther("1") * firstTokenBalance) / secondTokenBalance;
            const usdAmount = (dfiAmount * price) / ethers.parseEther("1");
            const amount = await hhCommunityLaunch.getTokenAmountByUsd(usdAmount);
            const amountTotal =
                (amount * (await hhCommunityLaunch.getTokenFactorBonus(2))) / BigInt(100);

            await stateRelayer.updateDEXInfo(
                ["dUSDT-DFI"],
                [
                    {
                        primaryTokenPrice: ethers.parseEther("1"),
                        volume24H: 0,
                        totalLiquidity: 0,
                        APR: 0,
                        firstTokenBalance: firstTokenBalance,
                        secondTokenBalance: secondTokenBalance,
                        rewards: 0,
                        commissions: 0,
                    },
                ],
                0,
                0,
            );

            await hhCommunityLaunch
                .connect(addr1)
                .buy(addr1.address, dusdAmount, erc20Token2.target, true, {
                    value: 0,
                });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );

            const vestingParams = await hhCommunityLaunch.vestingParams();

            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amountTotal);
            await expect(await vestingScheduleForHolder.duration).to.be.equal(
                vestingParams.duration * BigInt(2),
            );
            await expect(await vestingScheduleForHolder.slicePeriodSeconds).to.be.equal(
                vestingParams.slicePeriodSeconds,
            );

            await expect(await erc20Token2.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokens2Before + dusdAmount,
            );

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokensBefore - amountTotal,
            );

            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokensBefore - amountTotal,
            );
        });

        it("Should revert when buy jav tokens with dusd - tokensAmountByType < 0 ", async () => {
            const usdtAmount = ethers.parseEther("120");
            await erc20Token2.mint(addr1.address, usdtAmount);
            await erc20Token2.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);
            const firstTokenBalance = BigInt(313643539540840000000000);
            const secondTokenBalance = BigInt(3988438984219900000000000);
            await stateRelayer.updateDEXInfo(
                ["dUSDT-DFI"],
                [
                    {
                        primaryTokenPrice: ethers.parseEther("1"),
                        volume24H: 0,
                        totalLiquidity: 0,
                        APR: 0,
                        firstTokenBalance: firstTokenBalance,
                        secondTokenBalance: secondTokenBalance,
                        rewards: 0,
                        commissions: 0,
                    },
                ],
                0,
                0,
            );

            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .buy(addr1.address, usdtAmount, erc20Token2.target, true, {
                        value: 0,
                    }),
            ).to.be.revertedWith(
                "CommunityLaunch: Invalid amount to purchase for the selected token",
            );
        });

        it("Should buy jav tokens with dfi _isLongerVesting =  false", async () => {
            await helpers.mine(10);

            const buyNativeAmount = ethers.parseEther("1.0");
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokenBeforeFreezer = await erc20Token.balanceOf(freezerMock.target);

            const firstTokenBalance = BigInt(313643539540840000000000);
            const secondTokenBalance = BigInt(3988438984219900000000000);

            const price = (ethers.parseEther("1") * firstTokenBalance) / secondTokenBalance;

            const usdAmount = (buyNativeAmount * price) / ethers.parseEther("1");
            const tokensAmount = await hhCommunityLaunch.getTokenAmountByUsd(usdAmount);

            await stateRelayer.updateDEXInfo(
                ["dUSDT-DFI"],
                [
                    {
                        primaryTokenPrice: ethers.parseEther("1"),
                        volume24H: 0,
                        totalLiquidity: 0,
                        APR: 0,
                        firstTokenBalance: firstTokenBalance,
                        secondTokenBalance: secondTokenBalance,
                        rewards: 0,
                        commissions: 0,
                    },
                ],
                0,
                0,
            );

            await hhCommunityLaunch
                .connect(addr1)
                .buy(addr1.address, 0, erc20Token2.target, false, {
                    value: buyNativeAmount,
                });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(tokensAmount);

            await expect(await ethers.provider.getBalance(hhCommunityLaunch.target)).to.be.equal(
                buyNativeAmount,
            );

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - tokensAmount,
            );
            await expect(await erc20Token.balanceOf(freezerMock.target)).to.be.equal(
                tokenBeforeFreezer + tokensAmount,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokenBefore - tokensAmount,
            );
        });

        it("Should buy jav tokens with dfi _isLongerVesting =  true", async () => {
            await helpers.mine(10);

            const buyNativeAmount = ethers.parseEther("1.0");
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokenBeforeFreezer = await erc20Token.balanceOf(freezerMock.target);
            const nativeAmountBefore = await ethers.provider.getBalance(hhCommunityLaunch.target);

            const firstTokenBalance = BigInt(313643539540840000000000);
            const secondTokenBalance = BigInt(3988438984219900000000000);

            const price = (ethers.parseEther("1") * firstTokenBalance) / secondTokenBalance;

            const usdAmount = (buyNativeAmount * price) / ethers.parseEther("1");
            const tokensAmount = await hhCommunityLaunch.getTokenAmountByUsd(usdAmount);
            const amountTotal =
                (tokensAmount * (await hhCommunityLaunch.getTokenFactorBonus(0))) / BigInt(100);

            await stateRelayer.updateDEXInfo(
                ["dUSDT-DFI"],
                [
                    {
                        primaryTokenPrice: ethers.parseEther("1"),
                        volume24H: 0,
                        totalLiquidity: 0,
                        APR: 0,
                        firstTokenBalance: firstTokenBalance,
                        secondTokenBalance: secondTokenBalance,
                        rewards: 0,
                        commissions: 0,
                    },
                ],
                0,
                0,
            );

            await hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, erc20Token2.target, true, {
                value: buyNativeAmount,
            });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amountTotal);

            await expect(await ethers.provider.getBalance(hhCommunityLaunch.target)).to.be.equal(
                nativeAmountBefore + buyNativeAmount,
            );

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - amountTotal,
            );
            await expect(await erc20Token.balanceOf(freezerMock.target)).to.be.equal(
                tokenBeforeFreezer + amountTotal,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokenBefore - amountTotal,
            );
        });

        it("Should revert when withdraw ADMIN_ERROR", async () => {
            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .withdraw(erc20Token.target, addr1.address, ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when withdraw Invalid amount", async () => {
            await expect(
                hhCommunityLaunch.withdraw(
                    erc20Token.target,
                    addr1.address,
                    ethers.parseEther("150"),
                ),
            ).to.be.revertedWith("CommunityLaunch: Invalid amount");
        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.05");
            await erc20Token.mint(hhCommunityLaunch.target, amount);

            const balanceBefore = await erc20Token.balanceOf(addr1.address);

            await hhCommunityLaunch.withdraw(erc20Token.target, addr1.address, amount);

            await expect(await erc20Token.balanceOf(addr1.address)).to.equal(
                amount + balanceBefore,
            );
        });

        it("Should revert when withdrawDFI ADMIN_ERROR", async () => {
            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .withdrawDFI(addr1.address, ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when withdrawDFI Invalid amount", async () => {
            await expect(
                hhCommunityLaunch.withdrawDFI(addr1.address, ethers.parseEther("100")),
            ).to.be.revertedWith("CommunityLaunch: Invalid amount");
        });

        it("Should withdrawDFI", async () => {
            const amount = ethers.parseEther("0.05");
            const balanceBefore = await ethers.provider.getBalance(addr1.address);

            await hhCommunityLaunch.withdrawDFI(addr1.address, amount);

            await expect(await ethers.provider.getBalance(addr1.address)).to.equal(
                amount + balanceBefore,
            );
        });

        it("Should revert when simulateBuy - bot error", async () => {
            await expect(
                hhCommunityLaunch
                    .connect(addr1)
                    .simulateBuy(addr1.address, addr1.address, 1, false),
            ).to.be.revertedWith("CommunityLaunch: only bot");
        });

        it("Should simulateBuy _isBonus = False", async () => {
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const usdAmount = ethers.parseEther("5");
            const tokenAmount = await hhCommunityLaunch.getTokenAmountByUsd(usdAmount);

            await hhCommunityLaunch
                .connect(bot)
                .simulateBuy(addr1.address, addr1.address, usdAmount, false);

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(tokenAmount);

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - tokenAmount,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokenBefore - tokenAmount,
            );
        });

        it("Should simulateBuy _isBonus = True", async () => {
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const usdAmount = ethers.parseEther("5");
            const tokenAmount = await hhCommunityLaunch.getTokenAmountByUsd(usdAmount);
            const amountTotal =
                (tokenAmount * (await hhCommunityLaunch.getTokenFactorBonus(1))) / BigInt(100);

            await hhCommunityLaunch
                .connect(bot)
                .simulateBuy(addr1.address, addr1.address, usdAmount, true);

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amountTotal);

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - amountTotal,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokenBefore - amountTotal,
            );
        });

        it("Should simulateBuy - isSaleActive=False, _isBonus = False", async () => {
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const usdAmount = ethers.parseEther("5");
            const endTokenPrice = await hhCommunityLaunch.endTokenPrice();
            const tokenAmount = (usdAmount * ethers.parseEther("1")) / endTokenPrice;

            await hhCommunityLaunch.setSaleActive(false);
            await hhCommunityLaunch
                .connect(bot)
                .simulateBuy(addr1.address, addr1.address, usdAmount, false);

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(tokenAmount);

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - tokenAmount,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokenBefore - tokenAmount,
            );
        });

        it("Should simulateBuy - isSaleActive=False, _isBonus = true", async () => {
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const usdAmount = ethers.parseEther("5");
            const endTokenPrice = await hhCommunityLaunch.endTokenPrice();
            const tokenAmount = (usdAmount * ethers.parseEther("1")) / endTokenPrice;
            const amountTotal =
                (tokenAmount * (await hhCommunityLaunch.tokenFactor(1, 1))) / BigInt(100);

            await hhCommunityLaunch.setSaleActive(false);
            await hhCommunityLaunch
                .connect(bot)
                .simulateBuy(addr1.address, addr1.address, usdAmount, true);

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amountTotal);

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - amountTotal,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokenBefore - amountTotal,
            );
        });
    });
});
