const {expect} = require("chai");
const {ethers, upgrades} = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
    deployTokenFixture,
    deployToken2Fixture,
    deployUniswapFixture, deployStateRelayerFixture,
} = require("../common/mocks");
const {ADMIN_ERROR} = require("../common/constanst");

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
    let stateRelayer;
    let wdfiToken;
    let uniswapFactory;
    let uniswapRouter;
    let uniswapPairContract;
    let basePair;
    let vestingMock;
    let saleActiveError;
    let startTokenPrice;
    let incPricePerBlock;
    let startBlock;
    let dexPair;


    async function deployVestingFixture() {
        const tokenVestingFactory = await ethers.getContractFactory("TokenVesting");
        const freezerContractFactory = await ethers.getContractFactory("JavFreezerMock");
        const freezer = await freezerContractFactory.deploy();
        await freezer.waitForDeployment();

        const vestingMock = await upgrades.deployProxy(tokenVestingFactory, [freezer.target], {
            initializer: "initialize",
        });
        await vestingMock.waitForDeployment();
        return [vestingMock, freezer]
    }

    before(async () => {
        const communityLaunch = await ethers.getContractFactory("CommunityLaunch");

        [owner, addr1, addr2, admin, bot, ...addrs] = await ethers.getSigners();
        const nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        stateRelayer = await helpers.loadFixture(deployStateRelayerFixture);
        const vestingData = await deployVestingFixture()

        const data = await helpers.loadFixture(deployUniswapFixture);
        [wdfiToken, uniswapFactory, uniswapRouter, uniswapPairContract] = Object.values(data);
        [vestingMock, freezerMock] = vestingData

        startTokenPrice = ethers.parseEther("0.02");
        incPricePerBlock = ethers.parseEther("0.0000002");

        // create pairs
        await uniswapFactory.createPair(wdfiToken.target, erc20Token2.target);
        let allPairsLength = await uniswapFactory.allPairsLength();
        const pairCreated = await uniswapFactory.allPairs(allPairsLength - BigInt(1));
        basePair = uniswapPairContract.attach(pairCreated);

        hhCommunityLaunch = await upgrades.deployProxy(
            communityLaunch,
            [
                await erc20Token.getAddress(),
                stateRelayer.target,
                bot.address,
                await erc20Token2.getAddress(),
                basePair.target,
                vestingMock.target,
                freezerMock.target,
                startTokenPrice,
                incPricePerBlock,
                {
                    start: 100,
                    cliff: 200,
                    duration: 300,
                    slicePeriodSeconds: 50,
                },
            ],

            {
                initializer: "initialize",
            },
        );

        saleActiveError = "CommunityLaunch: contract is not available right now";
        dexPair = "DUSD-DFI"

        // add liquidity
        const amountWeth = ethers.parseEther("100");
        const amount0 = ethers.parseEther("500");
        await wdfiToken.deposit({value: amountWeth});
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

        it("Should set the right usdt address", async () => {
            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token2.target);
        });

        it("Should set the right pair address", async () => {
            await expect(await hhCommunityLaunch.pairAddress()).to.equal(basePair.target);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhCommunityLaunch.adminAddress()).to.equal(owner.address);
        });

        it("Should set the right vestingParams", async () => {
            const vestingParams = await hhCommunityLaunch.vestingParams();
            await expect(vestingParams[0]).to.equal(100);
            await expect(vestingParams[1]).to.equal(200);
            await expect(vestingParams[2]).to.equal(300);
            await expect(vestingParams[3]).to.equal(50);
        });

        it("Should set the right isSaleActive flag", async () => {
            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(false);
        });

        it("Should set the right startTokenPrice", async () => {
            await expect(await hhCommunityLaunch.startTokenPrice()).to.equal(startTokenPrice);
        });

        it("Should set the right incPricePerBlock", async () => {
            await expect(await hhCommunityLaunch.incPricePerBlock()).to.equal(incPricePerBlock);
        });

        it("Should mint tokens", async () => {
            const tokenAmounts = ethers.parseEther("20");

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
                }),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setVestingParams", async () => {
            await hhCommunityLaunch.setVestingParams({
                start: 200,
                cliff: 200,
                duration: 300,
                slicePeriodSeconds: 50,
            });

            const vestingParams = await hhCommunityLaunch.vestingParams();
            await expect(vestingParams[0]).to.equal(200);
            await expect(vestingParams[1]).to.equal(200);
            await expect(vestingParams[2]).to.equal(300);
            await expect(vestingParams[3]).to.equal(50);
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
            await hhCommunityLaunch.setUSDTAddress(erc20Token2.target);

            await expect(await hhCommunityLaunch.usdtAddress()).to.equal(erc20Token2.target);
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

        it("Should set the setSaleActive", async () => {
            await hhCommunityLaunch.setSaleActive(true);

            await expect(await hhCommunityLaunch.isSaleActive()).to.equal(true);
        });

        it("Should revert when set the setstartTokenPrice", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setStartTokenPrice(ethers.parseEther("0.0005")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setStartTokenPrice", async () => {
            startTokenPrice = ethers.parseEther("1");
            await hhCommunityLaunch.setStartTokenPrice(startTokenPrice);

            await expect(await hhCommunityLaunch.startTokenPrice()).to.equal(startTokenPrice);
        });

        it("Should revert when set the setStartBlock", async () => {
            await expect(hhCommunityLaunch.connect(addr1).setStartBlock(1)).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should set the setStartBlock", async () => {
            startBlock = (await helpers.time.latestBlock()) + 50;
            await hhCommunityLaunch.setStartBlock(startBlock);

            await expect(await hhCommunityLaunch.startBlock()).to.equal(startBlock);
        });

        it("Should revert when set the setIncPricePerBlock", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).setIncPricePerBlock(1),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the setIncPricePerBlock", async () => {
            incPricePerBlock = ethers.parseEther("0");

            await hhCommunityLaunch.setIncPricePerBlock(incPricePerBlock);

            await expect(await hhCommunityLaunch.incPricePerBlock()).to.equal(incPricePerBlock);
        });

        it("Should get the right tokenPrice when block.number > startBlock", async () => {
            const tokenPrice = await hhCommunityLaunch.startTokenPrice();

            await expect(await hhCommunityLaunch.tokenPrice()).to.equal(tokenPrice);
        });

        it("Should get the right tokenPrice when block.number < startBlock", async () => {
            await helpers.mine(100);

            const currentBlock = BigInt(await helpers.time.latestBlock());
            const price = (currentBlock - BigInt(startBlock)) * incPricePerBlock + startTokenPrice;

            await expect(await hhCommunityLaunch.tokenPrice()).to.equal(price);

            await hhCommunityLaunch.setStartBlock(currentBlock + BigInt(10));
        });

        it("Should get the right tokensBalance", async () => {
            await expect(await hhCommunityLaunch.tokensBalance()).to.equal(ethers.parseEther("20"));
        });

        it("Should revert when buy with isSaleActive = false", async () => {
            await hhCommunityLaunch.setSaleActive(false);

            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, {
                    value: ethers.parseEther("1.0"),
                }),
            ).to.be.revertedWith(saleActiveError);

            await hhCommunityLaunch.setSaleActive(true);
        });

        it("Should revert when buy with block.number >= startBlock", async () => {
            await expect(
                hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, {
                    value: ethers.parseEther("1.0"),
                }),
            ).to.be.revertedWith("CommunityLaunch: Need wait startBlock");
        });

        it("Should buy jav tokens with dusd", async () => {
            await helpers.mine(10);

            const usdtAmount = ethers.parseEther("5");
            await erc20Token2.mint(addr1.address, usdtAmount);
            await erc20Token2.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);
            const tokenBeforeFreezer = await erc20Token.balanceOf(freezerMock.target);

            const mintedTokens = ethers.parseEther("20");
            const tokenPrice = await hhCommunityLaunch.tokenPrice();
            const amount = ethers.parseEther((usdtAmount / tokenPrice).toString());

            await hhCommunityLaunch.connect(addr1).buy(addr1.address, usdtAmount, true, {
                value: 0,
            });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );

            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amount);

            await expect(await erc20Token2.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                usdtAmount,
            );
            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                mintedTokens - amount,
            );
            await expect(await erc20Token.balanceOf(freezerMock.target)).to.be.equal(
                tokenBeforeFreezer + amount,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                mintedTokens - amount,
            );
        });

        it("Should buy jav tokens with dusd _isEqualUSD = false", async () => {
            await helpers.mine(10);

            const tokensBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokens2Before = await erc20Token2.balanceOf(hhCommunityLaunch.target);
            const usdtAmount = ethers.parseEther("5");
            await erc20Token2.mint(addr1.address, usdtAmount);
            await erc20Token2.connect(addr1).approve(hhCommunityLaunch.target, usdtAmount);

            const tokenPrice = await hhCommunityLaunch.tokenPrice();
            let amount = ethers.parseEther((usdtAmount / tokenPrice).toString());
            const dexDUSDPrice = ethers.parseEther("0.5")
            amount = ethers.parseEther((amount / dexDUSDPrice).toString());

            await stateRelayer.updateDEXInfo([dexPair], [{
                primaryTokenPrice: dexDUSDPrice,
                volume24H: 0,
                totalLiquidity: 0,
                APR: 0,
                firstTokenBalance: 0,
                secondTokenBalance: 0,
                rewards: 0,
                commissions: 0,
            }], 0, 0)

            await hhCommunityLaunch.connect(addr1).buy(addr1.address, usdtAmount, false, {
                value: 0,
            });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );

            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amount);

            await expect(await erc20Token2.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokens2Before + usdtAmount,
            );

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokensBefore - amount,
            );

            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(
                tokensBefore - amount,
            );
        });

        it("Should buy jav tokens with dfi", async () => {
            await helpers.mine(10);

            const buyNativeAmount = ethers.parseEther("1.0");
            const tokenBefore = await erc20Token.balanceOf(hhCommunityLaunch.target);
            const tokenBeforeFreezer = await erc20Token.balanceOf(freezerMock.target);
            let amount = ethers.parseEther("5");

            const dexDUSDPrice = ethers.parseEther("1")
            amount = ethers.parseEther((amount / dexDUSDPrice).toString());

            await stateRelayer.updateDEXInfo([dexPair], [{
                primaryTokenPrice: dexDUSDPrice,
                volume24H: 0,
                totalLiquidity: 0,
                APR: 0,
                firstTokenBalance: 0,
                secondTokenBalance: 0,
                rewards: 0,
                commissions: 0,
            }], 0, 0)

            await hhCommunityLaunch.connect(addr1).buy(addr1.address, 0, true, {
                value: buyNativeAmount,
            });

            const vestingScheduleForHolder = await vestingMock.getLastVestingScheduleForHolder(
                addr1.address,
            );
            await expect(await vestingScheduleForHolder.amountTotal).to.be.equal(amount);

            await expect(await ethers.provider.getBalance(hhCommunityLaunch.target)).to.be.equal(
                buyNativeAmount,
            );

            await expect(await erc20Token.balanceOf(hhCommunityLaunch.target)).to.be.equal(
                tokenBefore - amount,
            );
            await expect(await erc20Token.balanceOf(freezerMock.target)).to.be.equal(
                tokenBeforeFreezer + amount,
            );
            await expect(await hhCommunityLaunch.tokensBalance()).to.be.equal(tokenBefore - amount);
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
                    ethers.parseEther("100"),
                ),
            ).to.be.revertedWith("CommunityLaunch: Invalid amount");
        });

        it("Should withdraw", async () => {
            const amount = ethers.parseEther("0.05");
            await erc20Token.mint(hhCommunityLaunch.target, amount)

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
    });
});
