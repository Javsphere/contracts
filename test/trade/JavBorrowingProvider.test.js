const { expect } = require("chai");

const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployTokenFixture, deployTermsAndConditionsFixture } = require("../common/mocks");
const { ADMIN_ERROR, MANAGER_ERROR, MAX_UINT256, OWNER_ERROR } = require("../common/constanst");
const { parseUnits, parseEther } = require("ethers");
describe("JavBorrowingProvider contract", () => {
    let hhJavBorrowingProvider;
    let owner;
    let bot;
    let addr2;
    let addr3;
    let addr4;
    let pnlHandler;
    let javPriceAggregator;
    let javBurner;
    let javInfoAggregator;
    let nonZeroAddress;
    let erc20Token;
    let erc20Token2;
    let llpToken;
    let termsAndConditions;
    const token1PriceId = "0x12635656e5b860830354ee353bce5f76d17342f9dbb560e3180d878b5d53bae3";
    const token2PriceId = "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6";

    const MIN_BUY_AMOUNT_USD = 5;
    const INITIAL_TOKEN_BUY = parseUnits("1", 18);

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

    async function deployJavBurner() {
        const javBurnerFactory = await ethers.getContractFactory("JavBurnerMock");
        const javBurner = await upgrades.deployProxy(javBurnerFactory, [], {
            initializer: "initialize",
        });

        await javBurner.waitForDeployment();

        return javBurner;
    }

    async function deployJavInfoAggregator() {
        const javInfoAggregatorContractFactory = await ethers.getContractFactory(
            "JavInfoAggregatorMock",
        );
        const javInfoAggregator = await javInfoAggregatorContractFactory.deploy();
        await javInfoAggregator.waitForDeployment();
        return javInfoAggregator;
    }

    async function mintApproveToken(user, token, amount) {
        await token.mint(user, amount);
        await token.connect(user).approve(hhJavBorrowingProvider.target, amount);
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
        [owner, bot, addr2, addr3, addr4, pnlHandler, ...addrs] = await ethers.getSigners();
        nonZeroAddress = ethers.Wallet.createRandom().address;
        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        llpToken = await helpers.loadFixture(deployLLPToken);
        javPriceAggregator = await helpers.loadFixture(deployJavPriceAggregator);
        termsAndConditions = await helpers.loadFixture(deployTermsAndConditionsFixture);
        javBurner = await helpers.loadFixture(deployJavBurner);
        javInfoAggregator = await helpers.loadFixture(deployJavInfoAggregator);

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
                    {
                        asset: erc20Token2.target,
                        priceFeed: token2PriceId,
                        targetWeightage: 20,
                        isActive: false,
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
                [100, 1000, 5000, 10000, 25000, 50000, 100000, 500000],
            );
            await hhJavBorrowingProvider.setJavAmountConfiguration(
                [0, 100000, 250000, 500000, 1000000],
                [10000, 7500, 5000, 2500, 1250],
            );
            await hhJavBorrowingProvider.setSellFees([300, 200, 100, 50, 25]);
        });
    });

    describe("Transactions", () => {
        it("Should revert when setTermsAndConditionsAddress - onlyAdmin", async () => {
            await expect(
                hhJavBorrowingProvider
                    .connect(bot)
                    .setTermsAndConditionsAddress(termsAndConditions.target),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setTermsAndConditionsAddress - nonZeroAddress", async () => {
            await expect(
                hhJavBorrowingProvider.setTermsAndConditionsAddress(
                    "0x0000000000000000000000000000000000000000",
                ),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "AddressZero");
        });

        it("Should revert when updateToken - token is inactive", async () => {
            const tokenUpdateInfo = {
                asset: erc20Token2.target,
                priceFeed: token2PriceId,
                targetWeightage: 20,
                isActive: false,
            };

            await expect(hhJavBorrowingProvider.updateToken(2, tokenUpdateInfo)).to.be.revertedWith(
                "JavBorrowingProvider: Token is inactive",
            );
        });

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

        it("Should revert when initialBuy - onlyAdmin", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).initialBuy(0, parseEther("1"), parseEther("1")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when initialBuy - Invalid Token", async () => {
            await expect(
                hhJavBorrowingProvider.initialBuy(3, parseEther("1"), parseEther("1")),
            ).to.be.revertedWith("JavBorrowingProvider: Invalid token");
        });

        it("Should revert when initialBuy - Purchase not available", async () => {
            await expect(
                hhJavBorrowingProvider.initialBuy(0, parseEther("1"), parseEther("1")),
            ).to.be.revertedWith("JavBorrowingProvider: Purchase not available");
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

        it("////////////////////////////////", async () => {});

        it("Should revert when addToken - onlyAdmin", async () => {
            const updatedTokenData = {
                asset: erc20Token.target,
                priceFeed: token1PriceId,
                targetWeightage: 50,
                isActive: false,
            };

            await expect(
                hhJavBorrowingProvider.connect(bot).addToken(updatedTokenData),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when updateToken - onlyAdmin", async () => {
            const updatedTokenData = {
                asset: erc20Token.target,
                priceFeed: token1PriceId,
                targetWeightage: 50,
                isActive: false,
            };

            await expect(
                hhJavBorrowingProvider.connect(bot).updateToken(0, updatedTokenData),
            ).to.be.revertedWith(ADMIN_ERROR);

            await expect(
                hhJavBorrowingProvider.updateToken(3, updatedTokenData),
            ).to.be.revertedWith("JavBorrowingProvider: Invalid token");
        });

        it("Should updateToken", async () => {
            const updatedTokenData = {
                asset: erc20Token.target,
                priceFeed: token1PriceId,
                targetWeightage: 40,
                isActive: true,
            };

            await expect(hhJavBorrowingProvider.connect(owner).updateToken(0, updatedTokenData))
                .to.emit(hhJavBorrowingProvider, "UpdateToken")
                .withArgs(
                    0,
                    updatedTokenData.asset,
                    updatedTokenData.priceFeed,
                    updatedTokenData.targetWeightage,
                    updatedTokenData.isActive,
                );

            expect((await hhJavBorrowingProvider.tokens(0))[2]).to.be.eq(
                updatedTokenData.targetWeightage,
            );
        });

        it("Should revert when setBuyConfiguration - onlyAdmin", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).setBuyConfiguration([], []),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setBuyConfiguration - InvalidInputLength", async () => {
            await expect(
                hhJavBorrowingProvider.setBuyConfiguration([], [1]),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "InvalidInputLength");
        });

        it("Should revert when setJavAmountConfiguration - onlyAdmin", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).setJavAmountConfiguration([], []),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when setJavAmountConfiguration - InvalidInputLength", async () => {
            await expect(
                hhJavBorrowingProvider.setJavAmountConfiguration([], [1]),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "InvalidInputLength");
        });

        it("Should revert when setSellFees - onlyAdmin", async () => {
            await expect(hhJavBorrowingProvider.connect(bot).setSellFees([1])).to.be.revertedWith(
                ADMIN_ERROR,
            );
        });

        it("Should revert when setSellFees - InvalidInputLength", async () => {
            await expect(hhJavBorrowingProvider.setSellFees([])).to.be.revertedWithCustomError(
                hhJavBorrowingProvider,
                "InvalidInputLength",
            );
        });

        it("Should revert when toggleSellActiveState", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).toggleSellActiveState(),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should toggleSellActiveState", async () => {
            await expect(hhJavBorrowingProvider.toggleSellActiveState())
                .to.emit(hhJavBorrowingProvider, "SellActiveStateUpdated")
                .withArgs(true);
        });

        it("Should revert when setJavBurner", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).setJavBurner(javBurner.target),
            ).to.be.revertedWith(ADMIN_ERROR);

            await expect(
                hhJavBorrowingProvider.setJavBurner("0x0000000000000000000000000000000000000000"),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "AddressZero()");
        });

        it("Should setJavBurner", async () => {
            await expect(hhJavBorrowingProvider.setJavBurner(javBurner.target))
                .to.emit(hhJavBorrowingProvider, "SetJavBurner")
                .withArgs(javBurner.target);
        });

        it("Should revert when setJavInfoAggregator", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).setJavInfoAggregator(javInfoAggregator.target),
            ).to.be.revertedWith(ADMIN_ERROR);

            await expect(
                hhJavBorrowingProvider.setJavInfoAggregator(
                    "0x0000000000000000000000000000000000000000",
                ),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "AddressZero()");
        });

        it("Should setJavInfoAggregator", async () => {
            await expect(hhJavBorrowingProvider.setJavInfoAggregator(javInfoAggregator.target))
                .to.emit(hhJavBorrowingProvider, "SetJavInfoAggregator")
                .withArgs(javInfoAggregator.target);
        });

        it("Should revert when setMinBuyAmountUsd", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).setMinBuyAmountUsd(5),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should setMinBuyAmountUsd", async () => {
            await expect(hhJavBorrowingProvider.setMinBuyAmountUsd(MIN_BUY_AMOUNT_USD))
                .to.emit(hhJavBorrowingProvider, "SetMinBuyAmountUsd")
                .withArgs(MIN_BUY_AMOUNT_USD);
        });

        it("Should revert when buyLLP - InvalidToken", async () => {
            await expect(hhJavBorrowingProvider.buyLLP(3, 100)).to.be.revertedWith(
                "JavBorrowingProvider: Invalid token",
            );
        });

        it("Should revert when buyLLP - whenNotPaused", async () => {
            await hhJavBorrowingProvider.pause();
            await expect(hhJavBorrowingProvider.buyLLP(2, 100)).to.be.revertedWithCustomError(
                hhJavBorrowingProvider,
                "EnforcedPause()",
            );
            await hhJavBorrowingProvider.unpause();
        });

        it("Should revert when buyLLP - invalid balance for buy", async () => {
            await termsAndConditions.connect(addr3).agreeToTerms();

            await expect(hhJavBorrowingProvider.connect(addr3).buyLLP(0, 100)).to.be.revertedWith(
                "JavBorrowingProvider: invalid balance for buy",
            );
        });

        it("Should revert when buyLLP - BelowMinBuyAmount", async () => {
            await mintApproveToken(addr2, erc20Token, 4);
            await expect(
                hhJavBorrowingProvider.connect(addr2).buyLLP(0, 4),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "BelowMinBuyAmount()");
        });

        it("Should buyLLP", async () => {
            const amount = parseUnits("100", 18);
            const precision = parseUnits("1", 4);

            await mintApproveToken(addr3, erc20Token, amount);

            expect(await erc20Token.balanceOf(addr3)).to.be.eq(amount);
            expect(await llpToken.balanceOf(owner)).to.be.equal(INITIAL_TOKEN_BUY);

            const feeP = 200n;
            const inputOutputTokenAmount = (amount * (precision - feeP)) / precision;
            const feeAmount = amount - inputOutputTokenAmount;

            await expect(hhJavBorrowingProvider.connect(addr3).buyLLP(0, amount))
                .to.emit(hhJavBorrowingProvider, "BuyLLP")
                .withArgs(
                    addr3,
                    erc20Token,
                    0,
                    llpToken,
                    amount,
                    inputOutputTokenAmount,
                    feeAmount,
                    feeAmount,
                );

            expect(await erc20Token.balanceOf(addr3)).to.be.equal(0);
            expect(await erc20Token.balanceOf(javBurner.target)).to.equal(0);
            expect(await llpToken.balanceOf(addr3)).to.be.equal(inputOutputTokenAmount);
            expect(await hhJavBorrowingProvider.tokenAmount(0)).to.be.equal(
                INITIAL_TOKEN_BUY + inputOutputTokenAmount,
            );
        });

        it("Should revert when sellLLP - onlyActiveSell", async () => {
            await hhJavBorrowingProvider.toggleSellActiveState();
            await expect(
                hhJavBorrowingProvider.connect(addr3).sellLLP(1, 1),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "InactiveSell");
            await hhJavBorrowingProvider.toggleSellActiveState();
        });

        it("Should revert when sellLLP - whenNotPaused", async () => {
            await hhJavBorrowingProvider.pause();
            await expect(
                hhJavBorrowingProvider.connect(addr3).sellLLP(1, 1),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "EnforcedPause");
            await hhJavBorrowingProvider.unpause();
        });

        it("Should revert when sellLLP - InvalidToken", async () => {
            await expect(hhJavBorrowingProvider.sellLLP(3, 1)).to.be.revertedWith(
                "JavBorrowingProvider: Invalid token",
            );
        });

        it("Should revert when sellLLP - invalid balance for sell", async () => {
            await expect(hhJavBorrowingProvider.connect(addr2).sellLLP(0, 1)).to.be.revertedWith(
                "JavBorrowingProvider: invalid balance for sell",
            );
        });

        it("Should sellLLP", async () => {
            const amount = parseUnits("100", 18);
            const precision = parseUnits("1", 4);
            const feeP = 200n;
            const inputOutputTokenAmount = (amount * (precision - feeP)) / precision;
            const feeAmount = amount - inputOutputTokenAmount;

            const sellFeeP = 300n;
            const newInputOutputTokenAmount =
                (inputOutputTokenAmount * (precision - sellFeeP)) / precision;

            await llpToken.connect(addr3).approve(hhJavBorrowingProvider, inputOutputTokenAmount);
            await hhJavBorrowingProvider.connect(addr3).sellLLP(0, inputOutputTokenAmount);

            expect(await erc20Token.balanceOf(addr3)).to.be.equal(newInputOutputTokenAmount);
            expect(await erc20Token.balanceOf(javBurner.target)).to.equal(0);
            expect(await llpToken.balanceOf(addr3)).to.be.equal(0);
            expect(await hhJavBorrowingProvider.tokenAmount(0)).to.be.equal(INITIAL_TOKEN_BUY);
        });

        it("Should revert when updatePnlHandler - onlyOwner", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).updatePnlHandler(pnlHandler),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, OWNER_ERROR);
        });

        it("Should revert when updatePnlHandler - AddressZero", async () => {
            await expect(
                hhJavBorrowingProvider
                    .connect(owner)
                    .updatePnlHandler("0x0000000000000000000000000000000000000000"),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "AddressZero");
        });

        it("Should updatePnlHandler", async () => {
            await expect(hhJavBorrowingProvider.connect(owner).updatePnlHandler(pnlHandler))
                .to.emit(hhJavBorrowingProvider, "PnlHandlerUpdated")
                .withArgs(pnlHandler);
        });

        it("Should revert when sendAssets - Invalid token", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).sendAssets(3, parseEther("2"), addr4),
            ).to.be.revertedWith("JavBorrowingProvider: Invalid token");
        });

        it("Should revert when sendAssets - OnlyTradingPnlHandler", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).sendAssets(0, parseEther("2"), addr4),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "OnlyTradingPnlHandler");
        });

        it("Should revert when sendAssets - NotEnoughAssets", async () => {
            await expect(
                hhJavBorrowingProvider.connect(pnlHandler).sendAssets(0, parseEther("2"), addr4),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "NotEnoughAssets");
        });

        it("Should sendAssets", async () => {
            await expect(
                hhJavBorrowingProvider.connect(pnlHandler).sendAssets(0, parseEther("1"), addr4),
            )
                .to.emit(hhJavBorrowingProvider, "AssetsSent")
                .withArgs(pnlHandler, addr4, parseEther("1"));

            expect(await hhJavBorrowingProvider.accPnlPerToken(0)).to.be.eq(parseEther("1"));
            expect(await hhJavBorrowingProvider.tokenAmount(0)).to.be.eq(0);
            expect(await erc20Token.balanceOf(addr4)).to.be.eq(parseEther("1"));
        });

        it("Should revert when receiveAssets - Invalid token", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).receiveAssets(3, parseEther("2"), addr4),
            ).to.be.revertedWith("JavBorrowingProvider: Invalid token");
        });

        it("Should receiveAssets", async () => {
            await erc20Token.connect(addr4).approve(hhJavBorrowingProvider, parseEther("1"));
            const zeroAddress = "0x0000000000000000000000000000000000000000";
            await expect(
                hhJavBorrowingProvider
                    .connect(addr4)
                    .receiveAssets(0, parseEther("1"), zeroAddress),
            )
                .to.emit(hhJavBorrowingProvider, "AssetsReceived")
                .withArgs(addr4, zeroAddress, parseEther("1"), parseEther("1"));

            expect(await hhJavBorrowingProvider.accPnlPerToken(0)).to.be.eq(0);
            expect(await hhJavBorrowingProvider.tokenAmount(0)).to.be.eq(parseEther("1"));
            expect(await erc20Token.balanceOf(addr4)).to.be.eq(0);
        });

        it("Should revert when distributeReward - Invalid token", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).distributeReward(3, parseEther("2")),
            ).to.be.revertedWith("JavBorrowingProvider: Invalid token");
        });

        it("Should distributeReward", async () => {
            await erc20Token.mint(addr4, parseEther("1"));
            await erc20Token.connect(addr4).approve(hhJavBorrowingProvider, parseEther("1"));

            await expect(hhJavBorrowingProvider.connect(addr4).distributeReward(0, parseEther("1")))
                .to.emit(hhJavBorrowingProvider, "RewardDistributed")
                .withArgs(addr4, 0, parseEther("1"), parseEther("1"));

            expect(await hhJavBorrowingProvider.accRewardsPerToken(0)).to.be.eq(parseEther("1"));
            expect(await hhJavBorrowingProvider.rewardsAmountUsd()).to.be.eq(parseEther("1"));
            expect(await erc20Token.balanceOf(addr4)).to.be.eq(0);
        });

        it("Should revert when sendAssets - NotEnoughAssets 2", async () => {
            await expect(
                hhJavBorrowingProvider.connect(pnlHandler).sendAssets(0, parseEther("2"), addr4),
            ).to.be.revertedWithCustomError(hhJavBorrowingProvider, "NotEnoughAssets");
        });

        it("Should revert when addLiquidity - onlyAdmin", async () => {
            await expect(
                hhJavBorrowingProvider.connect(bot).addLiquidity(0, parseEther("1")),
            ).to.be.revertedWith(ADMIN_ERROR);
        });

        it("Should revert when addLiquidity - Invalid token", async () => {
            await expect(
                hhJavBorrowingProvider.connect(owner).addLiquidity(3, parseEther("1")),
            ).to.be.revertedWith("JavBorrowingProvider: Invalid token");
        });

        it("Should revert when addLiquidity - invalid balance add liquidity", async () => {
            await expect(
                hhJavBorrowingProvider.connect(owner).addLiquidity(0, parseEther("1")),
            ).to.be.revertedWith("JavBorrowingProvider: invalid balance add liquidity");
        });

        it("Should addLiquidity", async () => {
            await mintApproveToken(owner, erc20Token, parseEther("1"));

            await expect(hhJavBorrowingProvider.connect(owner).addLiquidity(0, parseEther("1")))
                .to.emit(hhJavBorrowingProvider, "AddLiquidity")
                .withArgs(0, parseEther("1"));

            expect(await erc20Token.balanceOf(owner)).to.be.eq(0);
            expect(await hhJavBorrowingProvider.tokenAmount(0)).to.be.eq(parseEther("2")); //initial_amount_buy + liquidity added
        });

        it("Should receiveAssets with negative PNL", async () => {
            await erc20Token.mint(addr4, parseEther("20"));
            await erc20Token.connect(addr4).approve(hhJavBorrowingProvider, parseEther("20"));

            await hhJavBorrowingProvider
                .connect(addr4)
                .receiveAssets(0, parseEther("10"), "0x0000000000000000000000000000000000000000");

            await hhJavBorrowingProvider
                .connect(addr4)
                .receiveAssets(0, parseEther("10"), "0x0000000000000000000000000000000000000000");

            expect(await hhJavBorrowingProvider.accPnlPerToken(0)).to.be.eq(-parseEther("20"));
        });

        // TODO: open function before tests
        // it("Should test calculateFeeP - isBuy=True", async () => {
        //     // 200 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("100"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(200);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(200);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(150);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(150);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(100);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("350000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(100);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(50);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(50);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(25);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("500"), //_usdAmount
        //             ethers.parseEther("1200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(25);
        //
        //     //165 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("1000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(165);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(165);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(123); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("150000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(123); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(82); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(82); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(41);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(41);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(20); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("1200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(20); //todo: rounding
        //
        //     //149 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("5000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(149);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(149);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(111);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(111);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(74);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(74);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(37);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(37);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(18); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("12000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(18); //todo: rounding
        //
        //     // 132 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("10000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(132);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(132);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(99);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(99);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(66);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(66);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(33);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("900000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(33);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(16); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("2000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(16); //todo: rounding
        //
        //     // 116 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("25000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(116);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(116);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(87);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(87);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(58);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(58);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(29);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("900000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(29);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(14);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("2000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(14);
        //
        //     // 99 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("50000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(99);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(99);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(74);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(74);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(49); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(49); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(24);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(24);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(12);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("2000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(12);
        //
        //     // 66 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("100000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(66);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(66);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(49); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(49); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(33);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(33);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(16); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(16); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(8);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("150000"), //_usdAmount
        //             ethers.parseEther("2000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(8);
        //
        //     // 33 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("5000000"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(33);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(33);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(24); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(24); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(16); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(16); //todo: rounding
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(8);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(8);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(4);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("1200000"), //_javFreezerAmount
        //             true, //_isBuy
        //         ),
        //     ).to.be.equal(4);
        // });

        // TODO: open function before tests
        // it("Should test calculateFeeP - isBuy=False", async () => {
        //     // 300 base fee
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("100"), //_usdAmount
        //             ethers.parseEther("0"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(300);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("3000"), //_usdAmount
        //             ethers.parseEther("90000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(300);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("7000"), //_usdAmount
        //             ethers.parseEther("100000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(200);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("15000"), //_usdAmount
        //             ethers.parseEther("200000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(200);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("250000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(100);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("35000"), //_usdAmount
        //             ethers.parseEther("450000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(100);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("500000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(50);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("80000"), //_usdAmount
        //             ethers.parseEther("800000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(50);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("1000000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(25);
        //     await expect(
        //         await hhJavBorrowingProvider.calculateFeeP(
        //             ethers.parseEther("6000000"), //_usdAmount
        //             ethers.parseEther("1200000"), //_javFreezerAmount
        //             false, //_isBuy
        //         ),
        //     ).to.be.equal(25);
        // });
    });

    describe("View functions", async () => {
        it("Should revert when tokenTvl - Invalid Token", async () => {
            await expect(hhJavBorrowingProvider.tokenTvl(3)).to.be.revertedWith(
                "JavBorrowingProvider: Invalid token",
            );
        });
        it("Should return correct tokenTvl", async () => {
            expect(await hhJavBorrowingProvider.tokenTvl(0)).to.be.eq(parseEther("22")); //initial+rewards+20 for pnl testing
        });

        it("Should return correct tokensCount", async () => {
            expect(await hhJavBorrowingProvider.tokensCount()).to.be.eq(3);
        });

        it("Should revert when maxAccPnlPerToken - Invalid Token", async () => {
            await expect(hhJavBorrowingProvider.maxAccPnlPerToken(3)).to.be.revertedWith(
                "JavBorrowingProvider: Invalid token",
            );
        });
    });
});
