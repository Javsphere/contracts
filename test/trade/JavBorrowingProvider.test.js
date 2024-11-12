const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployTokenFixture } = require("../common/mocks");
const { ADMIN_ERROR, MANAGER_ERROR, MAX_UINT256 } = require("../common/constanst");
describe("JavBorrowingProvider contract", () => {
    let hhJavBorrowingProvider;
    let owner;
    let bot;
    let addr2;
    let addr3;
    let javPriceAggregator;
    let nonZeroAddress;
    let erc20Token;
    let erc20Token2;
    let llpToken;
    const token1PriceId = "0x12635656e5b860830354ee353bce5f76d17342f9dbb560e3180d878b5d53bae3";
    const token2PriceId = "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6";

    async function deployJavPriceAggregator() {
        const javPriceAggregatorFactory = await ethers.getContractFactory(
            "contracts/helpers/JavPriceAggregator.sol:JavPriceAggregator",
        );
        [owner, ...addrs] = await ethers.getSigners();
        const javPriceAggregator = await upgrades.deployProxy(
            javPriceAggregatorFactory,
            [1, [owner.address]],
            {
                initializer: "initialize",
            },
        );
        await javPriceAggregator.waitForDeployment();
        return javPriceAggregator;
    }

    async function deployLLPToken() {
        const llpTokenFactory = await ethers.getContractFactory("LLPToken");
        [owner, ...addrs] = await ethers.getSigners();
        const llpToken = await upgrades.deployProxy(llpTokenFactory, [], {
            initializer: "initialize",
        });
        await llpToken.waitForDeployment();
        return llpToken;
    }

    async function deployToken2Fixture() {
        const erc20ContractFactory = await ethers.getContractFactory("ERC20Mock");
        const erc20Token = await erc20ContractFactory.deploy("Mock2ERC20", "MOCK2", 6);
        await erc20Token.waitForDeployment();
        return erc20Token;
    }

    before(async () => {
        const JavBorrowingProvider = await ethers.getContractFactory("JavBorrowingProvider");
        [owner, bot, addr2, addr3, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        llpToken = await helpers.loadFixture(deployLLPToken);
        javPriceAggregator = await helpers.loadFixture(deployJavPriceAggregator);

        hhJavBorrowingProvider = await upgrades.deployProxy(
            JavBorrowingProvider,
            [
                javPriceAggregator.target, //  _priceAggregator,
                "0x0000000000000000000000000000000000000000", // _swapRouter,
                llpToken.target, //  _jlpToken,
                "0x0000000000000000000000000000000000000000", //  _pnlHandler,
                5, // _buyFee,
                6, // _sellFee,
                [
                    {
                        asset: erc20Token.target,
                        priceFeed: token1PriceId,
                        targetWeightage: 50,
                        isActive: true,
                    },
                    {
                        asset: erc20Token2.target,
                        priceFeed: token2PriceId,
                        targetWeightage: 20,
                        isActive: true,
                    },
                ], // _tokens
            ],
            {
                initializer: "initialize",
            },
        );
    });

    describe("Deployment", () => {
        it("Should set the right owner address", async () => {
            await expect(await hhJavBorrowingProvider.owner()).to.equal(owner.address);
        });

        it("Should set the right admin address", async () => {
            await expect(await hhJavBorrowingProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should set the _paused status", async () => {
            await expect(await hhJavBorrowingProvider.paused()).to.equal(false);
        });

        it("Should set prices for JavPriceAggregator", async () => {
            const AbiCoder = new ethers.AbiCoder();
            const updatePriceInfo1 = AbiCoder.encode(
                ["bytes32", "int64", "uint64", "int32", "uint64"],
                [token1PriceId, 10, 0, -1, 10000000000],
            );
            const updatePriceInfo2 = AbiCoder.encode(
                ["bytes32", "int64", "uint64", "int32", "uint64"],
                [token2PriceId, 20, 0, -1, 10000000000],
            );

            const messageHash1 = ethers.keccak256(updatePriceInfo1);
            const messageHash2 = ethers.keccak256(updatePriceInfo2);

            const signature1 = await owner.signMessage(ethers.getBytes(messageHash1));
            const signature2 = await owner.signMessage(ethers.getBytes(messageHash2));

            const signedData1 = ethers.concat([signature1, updatePriceInfo1]);
            const signedData2 = ethers.concat([signature2, updatePriceInfo2]);

            await javPriceAggregator.updatePriceFeeds([signedData1, signedData2], {
                value: 3,
            });
        });

        it("configuration", async () => {
            await llpToken.setBorrowingProvider(hhJavBorrowingProvider.target);
            await erc20Token.connect(owner).approve(hhJavBorrowingProvider.target, MAX_UINT256);
            await erc20Token2.connect(owner).approve(hhJavBorrowingProvider.target, MAX_UINT256);
            await erc20Token2.connect(addr2).approve(hhJavBorrowingProvider.target, MAX_UINT256);
        });
    });

    describe("Transactions", () => {
        it("Should revert when set pause", async () => {
            await expect(hhJavBorrowingProvider.connect(bot).pause()).to.be.revertedWith(
                MANAGER_ERROR,
            );
        });

        it("Should set pause", async () => {
            await hhJavBorrowingProvider.pause();

            await expect(await hhJavBorrowingProvider.paused()).to.equal(true);
        });

        it("Should revert when set unpause", async () => {
            await expect(hhJavBorrowingProvider.connect(bot).unpause()).to.be.revertedWith(
                MANAGER_ERROR,
            );
        });

        it("Should set unpause", async () => {
            await hhJavBorrowingProvider.unpause();

            await expect(await hhJavBorrowingProvider.paused()).to.equal(false);
        });

        it("Should revert when set the admin address", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).setAdminAddress(owner.address),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should set the admin address", async () => {
            await hhJavBorrowingProvider.setAdminAddress(owner.address);

            await expect(await hhJavBorrowingProvider.adminAddress()).to.equal(owner.address);
        });

        it("Should get tvl = 0", async () => {
            await expect(await hhJavBorrowingProvider.tvl()).to.equal(0);
        });

        it("Should get tvl = 0 with tokens when just transfer tokens", async () => {
            const amount1 = ethers.parseEther("50"); //50 usd
            const amount2 = ethers.parseEther("50"); //100 usd
            const amount3 = ethers.parseEther("50"); //250 usd

            await erc20Token.mint(hhJavBorrowingProvider.target, amount1);
            await erc20Token2.mint(hhJavBorrowingProvider.target, amount2);

            await expect(await hhJavBorrowingProvider.tvl()).to.equal(ethers.parseEther("0"));
        });

        it("Should initial buy", async () => {
            const amount1 = ethers.parseEther("1");
            await erc20Token.mint(owner.address, amount1);

            await hhJavBorrowingProvider.initialBuy(0, amount1, amount1);

            await expect(await erc20Token.balanceOf(owner.address)).to.be.equal(0);
            await expect(await llpToken.balanceOf(owner.address)).to.be.equal(amount1);
            await expect(await hhJavBorrowingProvider.tokenAmount(0)).to.be.equal(amount1);

            await expect(await hhJavBorrowingProvider.llpPrice()).to.equal(ethers.parseEther("1"));
        });

        it("Should buyLLP", async () => {
            const amount = ethers.parseUnits("1", 6);
            await erc20Token2.mint(addr2.address, amount);

            await hhJavBorrowingProvider.connect(addr2).buyLLP(1, amount);

            await expect(await erc20Token2.balanceOf(addr2.address)).to.be.equal(0);
            await expect(await llpToken.balanceOf(addr2.address)).to.be.equal(amount * BigInt(2));
            await expect(await hhJavBorrowingProvider.tokenAmount(1)).to.be.equal(amount);
        });

        // it("Should rebalance", async () => {
        //     const tvlBefore = await hhJavBorrowingProvider.tvl();
        //     const token1TvlBefore = await hhJavBorrowingProvider.tokenTvl(0);
        //     const token2TvlBefore = await hhJavBorrowingProvider.tokenTvl(1);
        //     const token3TvlBefore = await hhJavBorrowingProvider.tokenTvl(2);
        //     //
        //     // console.log("token1TvlBefore", token1TvlBefore);
        //     // console.log("token2TvlBefore", token2TvlBefore);
        //     // console.log("token2TvlBefore", token3TvlBefore);
        //     // console.log("tvlBefore", tvlBefore);
        //
        //     await hhJavBorrowingProvider.rebalanceTokens();
        //
        //     const tvl = await hhJavBorrowingProvider.tvl();
        //     const token1Tvl = await hhJavBorrowingProvider.tokenTvl(0);
        //     const token2Tvl = await hhJavBorrowingProvider.tokenTvl(1);
        //     const token3Tvl = await hhJavBorrowingProvider.tokenTvl(2);
        //
        //     // console.log("token1Tvl", token1Tvl);
        //     // console.log("token2Tvl", token2Tvl);
        //     // console.log("token3Tvl", token3Tvl);
        //     // console.log("tvl", tvl);
        //
        //     // await expect(await hhJavBorrowingProvider.tvl()).to.equal(ethers.parseEther("400"));
        // });
    });
});
