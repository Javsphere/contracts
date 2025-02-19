const {expect} = require("chai");
const {ethers, upgrades} = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {deployTokenFixture, deployTermsAndConditionsFixture} = require("../common/mocks");
const {ADMIN_ERROR, MANAGER_ERROR, MAX_UINT256} = require("../common/constanst");
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
    let termsAndConditions;
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
        termsAndConditions = await helpers.loadFixture(deployTermsAndConditionsFixture);

        hhJavBorrowingProvider = await upgrades.deployProxy(
            JavBorrowingProvider,
            [
                javPriceAggregator.target, //  _priceAggregator,
                "0x0000000000000000000000000000000000000000", // _swapRouter,
                llpToken.target, //  _jlpToken,
                "0x0000000000000000000000000000000000000000", //  _pnlHandler,
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
            await hhJavBorrowingProvider.setTermsAndConditionsAddress(termsAndConditions.target);
            await hhJavBorrowingProvider.setBuyConfiguration(
                [200, 165, 149, 132, 116, 99, 66, 33],
                [100, 1000, 5000, 10000, 25000, 50000, 100000, 500000]
            );
            await hhJavBorrowingProvider.setJavAmountConfiguration(
                [0, 100000, 250000, 500000, 1000000],
                [10000, 7500, 5000, 2500, 1250]
            );
            await hhJavBorrowingProvider.setSellFees(
                [300, 200, 100, 50, 25]
            );
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

        it("Should revert when toggleBuyActiveState", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).toggleBuyActiveState(),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when toggleSellActiveState", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).toggleSellActiveState(),
            ).to.be.revertedWith(ADMIN_ERROR);
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

        it("Should revert when buyLLP - InactiveBuy", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).buyLLP(1, 1),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "InactiveBuy");
        });

        it("Should toggleBuyActiveState", async () => {
            await hhJavBorrowingProvider.toggleBuyActiveState();
            await expect(await hhJavBorrowingProvider.isBuyActive()).to.be.equal(true);
        });


        it("Should revert when buyLLP - OnlyAgreedToTerms", async () => {
            await expect(
                hhJavBorrowingProvider.connect(addr2).buyLLP(1, 1),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "OnlyAgreedToTerms");

            await termsAndConditions.connect(addr2).agreeToTerms();
        });

        // it("Should buyLLP", async () => {
        //     const amount = ethers.parseUnits("1", 6);
        //     await erc20Token2.mint(addr2.address, amount);
        //
        //     const usdAmount = amount * BigInt(2) * ethers.parseUnits("1", 12);
        //     const fee =
        //         ((await hhJavBorrowingProvider.buyFee()) * usdAmount) / ethers.parseUnits("1", 4);
        //     const tokenAmounts =
        //         ((usdAmount - fee) * ethers.parseUnits("1", 18)) /
        //         (await hhJavBorrowingProvider.llpPrice());
        //
        //     await hhJavBorrowingProvider.connect(addr2).buyLLP(1, amount);
        //
        //     await expect(await erc20Token2.balanceOf(addr2.address)).to.be.equal(0);
        //     await expect(await llpToken.balanceOf(addr2.address)).to.be.equal(tokenAmounts);
        //     await expect(await hhJavBorrowingProvider.tokenAmount(1)).to.be.equal(amount);
        // });
        //
        // it("Should revert when sellLLP - InactiveSell", async () => {
        //     await expect(
        //         hhJavBorrowingProvider.connect(bot).sellLLP(1, 1),
        //     ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "InactiveSell");
        // });
        //
        // it("Should toggleBuyActiveState", async () => {
        //     await hhJavBorrowingProvider.toggleSellActiveState();
        //     await expect(await hhJavBorrowingProvider.isSellActive()).to.be.equal(true);
        // });
        //
        // it("Should revert when sellLLP - OnlyWhiteList", async () => {
        //     await expect(
        //         hhJavBorrowingProvider.connect(bot).sellLLP(1, 1),
        //     ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "OnlyWhiteList");
        // });

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

        it("Should test calculateFeeP - isBuy=True", async () => {
            // 200 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("100"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(200);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(200);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(150);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(150);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(100);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("350000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(100);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(50);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(50);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(25);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("500"), //_usdAmount
                ethers.parseEther("1200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(25);

            //165 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("1000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(165);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(165);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(123); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("150000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(123); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(82); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(82); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(41);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(41);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(20); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("1200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(20); //todo: rounding


            //149 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("5000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(149);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(149);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(111);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(111);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(74);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(74);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(37);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(37);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(18); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("12000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(18); //todo: rounding

            // 132 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("10000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(132);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(132);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(99);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(99);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(66);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(66);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(33);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("900000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(33);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(16); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("2000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(16); //todo: rounding

            // 116 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("25000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(116);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(116);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(87);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(87);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(58);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(58);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(29);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("900000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(29);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(14);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("2000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(14);

            // 99 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("50000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(99);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(99);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(74);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(74);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(49); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(49); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(24);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(24);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(12);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("2000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(12);

            // 66 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("100000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(66);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(66);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(49); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(49); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(33);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(33);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(16); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(16); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(8);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("150000"), //_usdAmount
                ethers.parseEther("2000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(8);

            // 33 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("5000000"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(33);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(33);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(24);//todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(24);//todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(16); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(16); //todo: rounding
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(8);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(8);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(4);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("1200000"), //_javFreezerAmount
                true //_isBuy
            )).to.be.equal(4);
        });

        it("Should test calculateFeeP - isBuy=False", async () => {
            // 300 base fee
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("100"), //_usdAmount
                ethers.parseEther("0"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(300);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("3000"), //_usdAmount
                ethers.parseEther("90000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(300);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("7000"), //_usdAmount
                ethers.parseEther("100000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(200);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("15000"), //_usdAmount
                ethers.parseEther("200000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(200);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("250000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(100);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("35000"), //_usdAmount
                ethers.parseEther("450000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(100);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("500000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(50);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("80000"), //_usdAmount
                ethers.parseEther("800000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(50);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("1000000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(25);
            await expect(await hhJavBorrowingProvider.calculateFeeP(
                ethers.parseEther("6000000"), //_usdAmount
                ethers.parseEther("1200000"), //_javFreezerAmount
                false //_isBuy
            )).to.be.equal(25);
        });

    });
});
