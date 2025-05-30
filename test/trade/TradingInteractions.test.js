const { expect } = require("chai");
const { abi } = require("./DiamondAbi");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const {
    deployTokenFixture,
    deployToken2Fixture,
    deployTermsAndConditionsFixture,
} = require("../common/mocks");

const {
    jav_borrowing_fees_selectors,
    jav_fee_tiers_selectors,
    jav_pairs_storage_selectors,
    jav_price_aggregator_selectors,
    jav_price_impact_selectors,
    jav_referrals_selectors,
    jav_trading_interactions_selectors,
    jav_trading_orders_selectors,
    jav_trading_processing_selectors,
    jav_trading_storage_selectors,
    jav_trigger_rewards_selectors,
} = require("./constants");

const { parseUnits, parseEther, concat, getBytes } = require("ethers");

describe("Trades", () => {
    let owner;

    let trader1;
    let trader2;

    let signer1;
    let signer2;
    let signer3;

    let pnlHandler;

    let traders_trades_counters;

    let accPairOiLong = 0n;
    let accPairOiShort = 0n;

    let currentPricePair1;
    let currentPricePair2;

    let hhLeverageX;

    let multiCollatDiamond;
    let pairsStorage;
    let referrals;
    let feeTiers;
    let priceImpact;
    let tradingStorage;
    let tradingInteractions;
    let tradingProcessing;
    let borrowingFees;
    let priceAggregator;
    let triggerRewards;
    let tradingOrders;

    let erc20Token;
    let erc20Token2;
    let llpToken;

    let javPriceAggregator;
    let javBurner;
    let javInfoAggregator;
    let javBorrowingProvider;
    let termsAndConditions;
    let rewardsDistributor;

    const TOKEN1_PRICE_ID = "0x12635656e5b860830354ee353bce5f76d17342f9dbb560e3180d878b5d53bae3";
    const TOKEN2_PRICE_ID = "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6";
    const PAIR1_PRICE_ID = "0x2a01deaec9e51a579277b34b122399984d0bbf57e2458a7e42fecd2829867a0d";
    const PAIR2_PRICE_ID = "0x84d21c9f53a60bc712e9a0f77c3ba3d0fa114ca389562f7ad3ee8b9f21e6c5a4";
    const RANDOM_HASH = "0xa5d9e8f38cb70f2ef81bd21acb77cc934a1fc2e26b91c0b40db6cf69e3eb1527";

    const P_3 = parseUnits("1", 3);
    const P_9 = parseUnits("1", 9);
    const P_10 = parseUnits("1", 10);
    const P_18 = parseUnits("1", 18);

    const TRADE_TYPE_TRADE = 0;
    const TRADE_TYPE_LIMIT = 1;
    const TRADE_TYPE_STOP = 2;

    const TRIGGER_TYPE_LIMIT_OPEN = 2;
    const TRIGGER_TYPE_STOP_OPEN = 3;
    const TRIGGER_TYPE_TP_CLOSE = 4;
    const TRIGGER_TYPE_SL_CLOSE = 5;
    const TRIGGER_TYPE_LIQ_CLOSE = 6;

    const UPDATE_FEE_VALUE = ethers.parseEther("0.001");

    const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

    const PAIR_DEPTH_ABOVE_USD = 538790n;
    const PAIR_DEPTH_BELOW_USD = 576403n;

    const BORROWING_PAIR_FEE_PER_BLOCK = 640880n;
    const BORROWING_PAIR_MAX_OI = 139646560319n;

    const SL_LIQ_BUFFER_P = 10n * P_10;

    const TOTAL_POSITION_SIZE_FEEP_P = 375000000n;

    const TRADE_INPUT_COLLATERAL_AMOUNT = parseEther("1");
    const TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT = parseEther("1") / 5n;

    function getOpenPriceWithImpact(collateralAmount, leverage, isLong, currentPrice) {
        const windowOi = isLong ? accPairOiLong : accPairOiShort;
        const pairDepth = isLong ? PAIR_DEPTH_ABOVE_USD : PAIR_DEPTH_BELOW_USD;
        const direction = isLong ? 1n : -1n;

        return (
            currentPrice +
            (direction *
                (currentPrice * ((windowOi + (collateralAmount * leverage) / P_3 / 2n) * P_10))) /
                pairDepth /
                P_18 /
                2n /
                P_10 /
                100n
        );
    }

    function getOpenPriceCollateralChange(
        oldCollateralAmount,
        collateralDelta,
        leverage,
        currentPrice,
        oldOpenPrice,
        isLong,
    ) {
        const existingPnlCollateral = getPnlCollateral(
            oldCollateralAmount,
            leverage,
            currentPrice,
            oldOpenPrice,
            isLong,
        );

        const priceAfterImpact = getPriceAfterCollateralChange(
            oldCollateralAmount,
            collateralDelta,
            leverage,
            isLong,
            currentPrice,
        );

        const positionSizePlusPnlCollateral = getPositionSizePlusPnlCollateral(
            oldCollateralAmount,
            leverage,
            existingPnlCollateral,
        );

        return (
            (positionSizePlusPnlCollateral * oldOpenPrice +
                ((collateralDelta * leverage) / P_3) * priceAfterImpact) /
            (positionSizePlusPnlCollateral + (collateralDelta * leverage) / P_3)
        );
    }

    function getPriceAfterCollateralChange(
        collateralAmount,
        collateralDelta,
        leverage,
        isLong,
        currentPrice,
    ) {
        const pairDepth = isLong ? PAIR_DEPTH_ABOVE_USD : PAIR_DEPTH_BELOW_USD;
        const direction = isLong ? 1n : -1n;

        return (
            currentPrice +
            (direction *
                (currentPrice *
                    (((((collateralAmount * leverage) / P_3) * P_10) / P_10 +
                        (collateralDelta * leverage) / P_3 / 2n) *
                        P_10))) /
                pairDepth /
                P_18 /
                2n /
                P_10 /
                100n
        );
    }

    function getPositionSizePlusPnlCollateral(collateralAmount, leverage, existingPnlCollateral) {
        return existingPnlCollateral < 0
            ? (collateralAmount * leverage) / P_3 - existingPnlCollateral * -1n
            : (collateralAmount * leverage) / P_3 + existingPnlCollateral;
    }

    function getPartialTradePnlCollateral(
        oldCollateralAmount,
        collateralDelta,
        leverage,
        currentPrice,
        oldOpenPrice,
        isLong,
    ) {
        const existingPnlCollateral = getPnlCollateral(
            oldCollateralAmount,
            leverage,
            currentPrice,
            oldOpenPrice,
            isLong,
        );

        return (
            (existingPnlCollateral * collateralDelta * leverage) /
            P_3 /
            ((oldCollateralAmount * leverage) / P_3)
        );
    }

    function getPnlCollateral(collateralAmount, leverage, currentPrice, openPrice, isLong) {
        const priceDiff = isLong ? currentPrice - openPrice : openPrice - currentPrice;
        return (
            (((priceDiff * 100n * P_10 * leverage) / openPrice / P_3) * collateralAmount) /
            100n /
            P_10
        );
    }

    function getTradePureValue(profitP, collateralAmount, leverage, borrowingBlocks) {
        const borrowingFeeCollateral = getBorrowingFeeCollateral(
            borrowingBlocks,
            collateralAmount,
            leverage,
        );

        const closingFeeCollateral = getTotalTradeBaseFees();

        return (
            BigInt(collateralAmount) +
            (BigInt(collateralAmount) * profitP) / BigInt(P_10) / 100n -
            BigInt(borrowingFeeCollateral + closingFeeCollateral)
        );
    }

    function getPnlP(currentPrice, openPrice, leverage, isLong) {
        const priceDiff = isLong ? currentPrice - openPrice : openPrice - currentPrice;

        return (priceDiff * 100n * P_10 * leverage) / openPrice / P_3;
    }

    function getBorrowingFeeCollateral(blocks, collateralAmount, leverage) {
        const borrowingFeeP = getBorrowingFeeP(blocks, collateralAmount, leverage);
        const multiplier = borrowingFeeP > 0 ? 1n : -1n;

        return ((borrowingFeeP * collateralAmount * leverage) / P_3 / P_10 / 100n) * multiplier;
    }

    function getBorrowingFeeP(blocks, collateralAmount, leverage) {
        return (
            (((blocks * BORROWING_PAIR_FEE_PER_BLOCK * collateralAmount * leverage) / P_3) * P_10) /
            BORROWING_PAIR_MAX_OI /
            P_18
        );
    }

    function getTotalTradeBaseFees() {
        return (TRADE_INPUT_COLLATERAL_AMOUNT * TOTAL_POSITION_SIZE_FEEP_P) / P_10;
    }

    function getCollateralAmountLeverageUpdate(collateralAmount, oldLeverage, newLeverage) {
        return (collateralAmount * oldLeverage) / newLeverage;
    }

    function getCollateralAmountMinusBaseFees(collateralAmount) {
        return collateralAmount - (collateralAmount * TOTAL_POSITION_SIZE_FEEP_P) / P_10;
    }

    async function limitNewSl(groupIndex, newSl, openPrice, leverage, isLong) {
        const liqPnlThresholdP = await getLiqPnlThresholdP(groupIndex, leverage);
        const minSlPnlP = liqPnlThresholdP - SL_LIQ_BUFFER_P;
        const slDiff = (openPrice * minSlPnlP * P_3) / leverage / 100n / P_10;
        return isLong ? openPrice - slDiff : openPrice + slDiff;
    }

    async function getLiqPnlThresholdP(groupIndex, leverage) {
        [maxLiqSpreadP, startLiqThresholdP, endLiqThresholdP, startLeverage, endLeverage] =
            await hhLeverageX.getGroupLiquidationParams(groupIndex);
        return (
            startLiqThresholdP -
            ((leverage - startLeverage) * (startLiqThresholdP - endLiqThresholdP)) /
                (endLeverage - startLeverage)
        );
    }

    async function openTradeWithExpect(
        trader,
        pairIndex,
        leverage,
        isLong,
        isOpen,
        collateralIndex,
        tradeType,
        collateralAmount,
        openPrice,
        tp,
        sl,
        expectedEventName,
    ) {
        await burnToken(erc20Token, trader);
        await mintApproveToken(erc20Token, trader, hhLeverageX, collateralAmount);

        traders_trades_counters[trader.address] += 1;

        await expect(
            hhLeverageX.connect(trader).openTrade(
                {
                    user: trader.address,
                    index: traders_trades_counters[trader.address],
                    pairIndex: pairIndex,
                    leverage: leverage,
                    long: isLong,
                    isOpen: isOpen,
                    collateralIndex: collateralIndex,
                    tradeType: tradeType,
                    collateralAmount: collateralAmount,
                    openPrice: openPrice,
                    tp: tp,
                    sl: sl,
                    __placeholder: 0,
                },
                1000,
                ADDRESS_ZERO,
                [await generateMockPriceUpdate(owner, 1), await generateMockPriceUpdate(owner, 2)],
                {
                    value: UPDATE_FEE_VALUE,
                },
            ),
        ).to.emit(hhLeverageX, expectedEventName);

        const oi = (getCollateralAmountMinusBaseFees(collateralAmount) * leverage) / P_3;

        if (tradeType == TRADE_TYPE_TRADE) {
            isLong ? (accPairOiLong += oi) : (accPairOiShort += oi);
        }

        return traders_trades_counters[trader.address];
    }

    async function closeTradeMarketWithExpect(trader, expectedEventName) {
        const tradeIndex = traders_trades_counters[trader.address];

        await expect(
            hhLeverageX
                .connect(trader)
                .closeTradeMarket(
                    tradeIndex,
                    [
                        await generateMockPriceUpdate(owner, 1),
                        await generateMockPriceUpdate(owner, 2),
                    ],
                    {
                        value: UPDATE_FEE_VALUE,
                    },
                ),
        ).to.emit(hhLeverageX, expectedEventName);

        return tradeIndex;
    }

    async function triggerOrderWithExpect(trader, triggerType, expectedEventName) {
        const triggerTradeIndex = traders_trades_counters[trader.address];

        await expect(
            hhLeverageX.triggerOrder(
                packTriggerOrder(triggerType, trader.address, triggerTradeIndex),
                [await generateMockPriceUpdate(owner, 1), await generateMockPriceUpdate(owner, 2)],
                {
                    value: UPDATE_FEE_VALUE,
                },
            ),
        ).to.emit(hhLeverageX, expectedEventName);

        if (triggerType == TRIGGER_TYPE_LIMIT_OPEN || triggerType == TRIGGER_TYPE_STOP_OPEN) {
            traders_trades_counters[trader.address] += 1;
        }

        return traders_trades_counters[trader.address];
    }

    async function updateTpWithExpect(trader, newTp, expectedEventName) {
        const tradeIndex = traders_trades_counters[trader.address];
        await expect(hhLeverageX.connect(trader).updateTp(tradeIndex, newTp)).to.emit(
            hhLeverageX,
            expectedEventName,
        );
        return tradeIndex;
    }

    async function updateSlWithExpect(trader, newSL, expectedEventName) {
        const tradeIndex = traders_trades_counters[trader.address];
        await expect(hhLeverageX.connect(trader).updateSl(tradeIndex, newSL)).to.emit(
            hhLeverageX,
            expectedEventName,
        );
        return tradeIndex;
    }

    async function updateLeverageWithExpect(trader, newLeverage, expectedEventName) {
        const tradeIndex = traders_trades_counters[trader.address];

        await expect(
            hhLeverageX
                .connect(trader)
                .updateLeverage(
                    tradeIndex,
                    newLeverage,
                    [
                        await generateMockPriceUpdate(owner, 1),
                        await generateMockPriceUpdate(owner, 2),
                    ],
                    {
                        value: UPDATE_FEE_VALUE,
                    },
                ),
        ).to.emit(hhLeverageX, expectedEventName);

        return tradeIndex;
    }

    async function increasePositionSizeWithExpect(
        trader,
        collateralDelta,
        leverage,
        expectedOpenPrice,
        expectedEventName,
    ) {
        const tradeIndex = traders_trades_counters[trader.address];

        await mintApproveToken(erc20Token, trader, hhLeverageX.target, collateralDelta);

        await expect(
            hhLeverageX
                .connect(trader)
                .increasePositionSize(
                    tradeIndex,
                    collateralDelta,
                    leverage,
                    expectedOpenPrice,
                    1000,
                    [
                        await generateMockPriceUpdate(owner, 1),
                        await generateMockPriceUpdate(owner, 2),
                    ],
                    {
                        value: UPDATE_FEE_VALUE,
                    },
                ),
        ).to.emit(hhLeverageX, expectedEventName);

        return tradeIndex;
    }

    async function decreasePositionSizeWithExpect(
        trader,
        collateralDelta,
        leverageDelta,
        expectedEventName,
    ) {
        const tradeIndex = traders_trades_counters[trader.address];

        await expect(
            hhLeverageX
                .connect(trader)
                .decreasePositionSize(
                    tradeIndex,
                    collateralDelta,
                    leverageDelta,
                    [
                        await generateMockPriceUpdate(owner, 1),
                        await generateMockPriceUpdate(owner, 2),
                    ],
                    {
                        value: UPDATE_FEE_VALUE,
                    },
                ),
        ).to.emit(hhLeverageX, expectedEventName);

        return tradeIndex;
    }

    async function mintApproveToken(token, user, target, amount) {
        await token.mint(user, amount);
        await token.connect(user).approve(target, amount);
    }

    async function burnToken(token, user) {
        const amount = await token.balanceOf(user);
        await token.connect(user).burn(amount);
    }

    async function generateMockPriceUpdate(signer, basePrice, decimals = 18) {
        const feedId = "0x" + "ab".repeat(32);
        const expo = -decimals;
        const randomizedPrice = getRandomizedPrice(basePrice, decimals);
        const priceInt = BigInt(Math.floor(randomizedPrice * 10 ** decimals));
        const conf = 1;
        const publishTime = Math.floor(Date.now() / 1000);

        const updateInfo = {
            id: feedId,
            price: priceInt,
            conf,
            expo,
            publishTime,
        };

        const encodedData = encodeUpdatePriceInfo(updateInfo);
        const hash = ethers.keccak256(encodedData);
        const signature = await signer.signMessage(getBytes(hash));

        const updateData = concat([getBytes(signature), getBytes(encodedData)]);

        return [updateData];
    }

    function encodeUpdatePriceInfo(info) {
        const AbiCoder = new ethers.AbiCoder();

        return AbiCoder.encode(
            ["tuple(bytes32 id, int64 price, uint64 conf, int32 expo, uint64 publishTime)"],
            [[info.id, info.price, info.conf, info.expo, info.publishTime]],
        );
    }

    function packTriggerOrder(orderType, trader, index) {
        const orderTypeBig = BigInt(orderType) & 0xffn;
        const traderBig = BigInt(trader);
        const indexBig = BigInt(index) & 0xffffffffn;

        const packed = (indexBig << 168n) | (traderBig << 8n) | orderTypeBig;
        return packed;
    }

    function getRandomizedPrice(basePrice, decimals) {
        const now = Date.now();
        const seed = now % 1000000;
        const rand = Math.sin(seed) * 10000;
        const frac = rand - Math.floor(rand);
        const noise = frac * 0.05;
        const finalPrice = basePrice * (1 + noise);
        return parseFloat(finalPrice.toFixed(8));
    }

    async function setPricesForJavPriceAggregator() {
        await syncUpdatePriceLifetime();

        const AbiCoder = new ethers.AbiCoder();
        const updatePriceInfo1 = AbiCoder.encode(
            ["bytes32", "int64", "uint64", "int32", "uint64"],
            [TOKEN1_PRICE_ID, 10, 0, -1, BigInt(Math.floor(Date.now() / 1000))],
        );
        const updatePriceInfo2 = AbiCoder.encode(
            ["bytes32", "int64", "uint64", "int32", "uint64"],
            [TOKEN2_PRICE_ID, 20, 0, -1, BigInt(Math.floor(Date.now() / 1000))],
        );

        const updatePriceInfo3 = AbiCoder.encode(
            ["bytes32", "int64", "uint64", "int32", "uint64"],
            [PAIR1_PRICE_ID, 10, 0, -1, BigInt(Math.floor(Date.now() / 1000))],
        );

        const updatePriceInfo4 = AbiCoder.encode(
            ["bytes32", "int64", "uint64", "int32", "uint64"],
            [PAIR2_PRICE_ID, 10, 0, -1, BigInt(Math.floor(Date.now() / 1000))],
        );

        const messageHash1 = ethers.keccak256(updatePriceInfo1);
        const messageHash2 = ethers.keccak256(updatePriceInfo2);
        const messageHash3 = ethers.keccak256(updatePriceInfo3);
        const messageHash4 = ethers.keccak256(updatePriceInfo4);

        const signature1 = await owner.signMessage(ethers.getBytes(messageHash1));
        const signature2 = await owner.signMessage(ethers.getBytes(messageHash2));
        const signature3 = await owner.signMessage(ethers.getBytes(messageHash3));
        const signature4 = await owner.signMessage(ethers.getBytes(messageHash4));

        const signedData1 = ethers.concat([signature1, updatePriceInfo1]);
        const signedData2 = ethers.concat([signature2, updatePriceInfo2]);
        const signedData3 = ethers.concat([signature3, updatePriceInfo3]);
        const signedData4 = ethers.concat([signature4, updatePriceInfo4]);

        currentPricePair1 = P_10;
        currentPricePair2 = P_10;

        await javPriceAggregator.updatePriceFeeds(
            [signedData1, signedData2, signedData3, signedData4],
            {
                value: UPDATE_FEE_VALUE,
            },
        );
    }

    async function updatePriceFeed(price, priceFeedId, signer) {
        const pricePrecisionP_9 = price / P_9;

        const AbiCoder = new ethers.AbiCoder();

        const updatePriceInfo = AbiCoder.encode(
            ["bytes32", "int64", "uint64", "int32", "uint64"],
            [priceFeedId, pricePrecisionP_9, 0, -1, BigInt(Math.floor(Date.now() / 1000))],
        );

        const messageHash = ethers.keccak256(updatePriceInfo);
        const signature = await signer.signMessage(ethers.getBytes(messageHash));
        const signedData = ethers.concat([signature, updatePriceInfo]);

        await javPriceAggregator.updatePriceFeeds([signedData], {
            value: UPDATE_FEE_VALUE,
        });
    }

    async function syncUpdatePriceLifetime() {
        const blockNumber = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNumber);

        await javPriceAggregator.setUpdatePriceLifetime(block.timestamp);
    }

    async function deployRewardsDistributor() {
        const rewardsDistributorFactory = await ethers.getContractFactory("RewardsDistributorMock");
        const rewardsDistributor = await rewardsDistributorFactory.deploy();
        await rewardsDistributor.waitForDeployment();
        return rewardsDistributor;
    }

    async function deployJavPriceAggregator() {
        const javPriceAggregatorFactory = await ethers.getContractFactory(
            "contracts/helpers/JavPriceAggregator.sol:JavPriceAggregator",
        );
        const javPriceAggregator = await upgrades.deployProxy(
            javPriceAggregatorFactory,
            [1, [owner.address, signer1.address, signer2.address, signer3.address]],
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

    async function deployLLPToken() {
        const llpTokenFactory = await ethers.getContractFactory("LLPToken");
        llpToken = await upgrades.deployProxy(llpTokenFactory, [], {
            initializer: "initialize",
        });
        await llpToken.waitForDeployment();
        return llpToken;
    }

    async function diamondCut() {
        faceCuts = [
            {
                facetAddress: pairsStorage.target,
                action: 0,
                functionSelectors: jav_pairs_storage_selectors,
            },
            {
                facetAddress: referrals.target,
                action: 0,
                functionSelectors: jav_referrals_selectors,
            },
            {
                facetAddress: feeTiers.target,
                action: 0,
                functionSelectors: jav_fee_tiers_selectors,
            },
            {
                facetAddress: priceImpact.target,
                action: 0,
                functionSelectors: jav_price_impact_selectors,
            },
            {
                facetAddress: tradingStorage.target,
                action: 0,
                functionSelectors: jav_trading_storage_selectors,
            },
            {
                facetAddress: tradingInteractions.target,
                action: 0,
                functionSelectors: jav_trading_interactions_selectors,
            },
            {
                facetAddress: tradingProcessing.target,
                action: 0,
                functionSelectors: jav_trading_processing_selectors,
            },
            {
                facetAddress: borrowingFees.target,
                action: 0,
                functionSelectors: jav_borrowing_fees_selectors,
            },
            {
                facetAddress: priceAggregator.target,
                action: 0,
                functionSelectors: jav_price_aggregator_selectors,
            },
            {
                facetAddress: triggerRewards.target,
                action: 0,
                functionSelectors: jav_trigger_rewards_selectors,
            },
            {
                facetAddress: tradingOrders.target,
                action: 0,
                functionSelectors: jav_trading_orders_selectors,
            },
        ];

        await multiCollatDiamond.diamondCut(faceCuts, ADDRESS_ZERO, "0x");
    }

    before(async () => {
        [owner, trader1, trader2, pnlHandler, signer1, signer2, signer3, ...addrs] =
            await ethers.getSigners();

        traders_trades_counters = {
            [trader1.address]: -1,
            [trader2.address]: -1,
        };

        const PackingUtils = await ethers.getContractFactory("PackingUtils");
        const packlingUtils = await PackingUtils.deploy();

        const ArrayGetters = await ethers.getContractFactory("ArrayGetters");
        const arrayGetters = await ArrayGetters.deploy();

        const TradingCommonUtils = await ethers.getContractFactory("TradingCommonUtils");
        const tradingCommonUtils = await TradingCommonUtils.deploy();

        const UpdateLeverageUtils = await ethers.getContractFactory("UpdateLeverageUtils", {
            libraries: {
                "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                    tradingCommonUtils.target,
            },
        });
        const updateLeverageUtils = await UpdateLeverageUtils.deploy();

        const UpdatePositionSizeUtils = await ethers.getContractFactory("UpdatePositionSizeUtils", {
            libraries: {
                "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                    tradingCommonUtils.target,
            },
        });
        const updatePositionSizeUtils = await UpdatePositionSizeUtils.deploy();

        const multiCollatDiamondFactory = await ethers.getContractFactory("JavMultiCollatDiamond");
        multiCollatDiamond = await upgrades.deployProxy(
            multiCollatDiamondFactory,
            [owner.address],

            {
                initializer: "initialize",
                kind: "uups",
                unsafeAllow: ["missing-initializer"],
            },
        );
        await multiCollatDiamond.waitForDeployment();

        const pairsStorageFactory = await ethers.getContractFactory("JavPairsStorage");
        pairsStorage = await pairsStorageFactory.deploy();
        await pairsStorage.waitForDeployment();

        const referralsFactory = await ethers.getContractFactory("JavReferrals");
        referrals = await referralsFactory.deploy();
        await referrals.waitForDeployment();

        const feeTiersFactory = await ethers.getContractFactory("JavFeeTiers");
        feeTiers = await feeTiersFactory.deploy();
        await feeTiers.waitForDeployment();

        const priceImpactFactory = await ethers.getContractFactory("JavPriceImpact", {
            libraries: {
                "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                    tradingCommonUtils.target,
            },
        });
        priceImpact = await priceImpactFactory.deploy();
        await priceImpact.waitForDeployment();

        const tradingStorageFactory = await ethers.getContractFactory("JavTradingStorage", {
            libraries: {
                "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                    tradingCommonUtils.target,
                "contracts/libraries/leverageX/ArrayGetters.sol:ArrayGetters": arrayGetters.target,
            },
        });
        tradingStorage = await tradingStorageFactory.deploy();
        await tradingStorage.waitForDeployment();

        const tradingInteractionsFactory = await ethers.getContractFactory(
            "JavTradingInteractions",
            {
                libraries: {
                    "contracts/libraries/leverageX/PackingUtils.sol:PackingUtils":
                        packlingUtils.target,
                    "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                        tradingCommonUtils.target,
                    "contracts/libraries/leverageX/updateLeverage/UpdateLeverageUtils.sol:UpdateLeverageUtils":
                        updateLeverageUtils.target,
                    "contracts/libraries/leverageX/updatePositionSize/UpdatePositionSizeUtils.sol:UpdatePositionSizeUtils":
                        updatePositionSizeUtils.target,
                },
            },
        );
        tradingInteractions = await tradingInteractionsFactory.deploy();
        await tradingInteractions.waitForDeployment();

        const tradingProcessingFactory = await ethers.getContractFactory("JavTradingProcessing", {
            libraries: {
                "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                    tradingCommonUtils.target,
            },
        });
        tradingProcessing = await tradingProcessingFactory.deploy();
        await tradingProcessing.waitForDeployment();

        const borrowingFeesFactory = await ethers.getContractFactory("JavBorrowingFees", {
            libraries: {
                "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                    tradingCommonUtils.target,
            },
        });
        borrowingFees = await borrowingFeesFactory.deploy();
        await borrowingFees.waitForDeployment();

        const priceAggregatorFactory = await ethers.getContractFactory(
            "contracts/leverageX/JavPriceAggregator.sol:JavPriceAggregator",
        );
        priceAggregator = await priceAggregatorFactory.deploy();
        await priceAggregator.waitForDeployment();

        const triggerRewardsFactory = await ethers.getContractFactory("JavTriggerRewards");
        triggerRewards = await triggerRewardsFactory.deploy();
        await triggerRewards.waitForDeployment();

        const tradingOrdersFactory = await ethers.getContractFactory("JavTradingOrders", {
            libraries: {
                "contracts/libraries/leverageX/ArrayGetters.sol:ArrayGetters": arrayGetters.target,
            },
        });
        tradingOrders = await tradingOrdersFactory.deploy();
        await tradingOrders.waitForDeployment();

        await diamondCut();

        const leverageXInterface = new ethers.Interface(abi);
        hhLeverageX = new ethers.Contract(
            await multiCollatDiamond.getAddress(),
            leverageXInterface,
            owner,
        );

        erc20Token = await helpers.loadFixture(deployTokenFixture);
        erc20Token2 = await helpers.loadFixture(deployToken2Fixture);
        llpToken = await helpers.loadFixture(deployLLPToken);

        javPriceAggregator = await helpers.loadFixture(deployJavPriceAggregator);
        javBurner = await helpers.loadFixture(deployJavBurner);
        javInfoAggregator = await helpers.loadFixture(deployJavInfoAggregator);

        const javBorrowingProviderFactory = await ethers.getContractFactory("JavBorrowingProvider");

        javBorrowingProvider = await upgrades.deployProxy(
            javBorrowingProviderFactory,
            [
                javPriceAggregator.target, //  _priceAggregator,
                ADDRESS_ZERO, // _swapRouter,
                llpToken.target, //  _jlpToken,
                pnlHandler.address, //  _pnlHandler,
                [
                    {
                        asset: erc20Token.target,
                        priceFeed: TOKEN1_PRICE_ID,
                        targetWeightage: 50,
                        isActive: true,
                    },
                    {
                        asset: erc20Token2.target,
                        priceFeed: TOKEN2_PRICE_ID,
                        targetWeightage: 20,
                        isActive: true,
                    },
                ], // _tokens
            ],
            {
                initializer: "initialize",
            },
        );

        termsAndConditions = await helpers.loadFixture(deployTermsAndConditionsFixture);
        rewardsDistributor = await helpers.loadFixture(deployRewardsDistributor);
        await javBorrowingProvider.setTermsAndConditionsAddress(termsAndConditions);
        await javBorrowingProvider.updatePnlHandler(hhLeverageX);
    });

    describe("Deployment", () => {
        it("Configuration", async () => {
            await llpToken.setBorrowingProvider(javBorrowingProvider.target);

            await mintApproveToken(
                erc20Token,
                owner,
                javBorrowingProvider.target,
                parseEther("100"),
            );
            await javBorrowingProvider.initialBuy(0, parseEther("100"), parseEther("100"));

            await hhLeverageX.setRoles([owner, owner], [1, 2], [true, true]);

            await hhLeverageX.updateTermsAndConditionsAddress(termsAndConditions.target);

            await hhLeverageX.addGroups([{ name: "crypto", minLeverage: 2e3, maxLeverage: 150e3 }]);

            await hhLeverageX.initializePriceImpact(600, 5);

            await hhLeverageX.initializeTradingProcessing(33);

            await hhLeverageX.addFees([
                {
                    totalPositionSizeFeeP: TOTAL_POSITION_SIZE_FEEP_P,
                    totalLiqCollateralFeeP: 10 * 1e10,
                    minPositionSizeUsd: 100000,
                    __placeholder: 0,
                },
            ]);

            await hhLeverageX.addPairs([
                {
                    from: "ADA",
                    to: "USD",
                    feedId: PAIR1_PRICE_ID,
                    spreadP: 0,
                    groupIndex: 0,
                    feeIndex: 0,
                    altPriceOracle: false,
                },

                {
                    from: "AAVE",
                    to: "USD",
                    feedId: PAIR2_PRICE_ID,
                    spreadP: 0,
                    groupIndex: 0,
                    feeIndex: 0,
                    altPriceOracle: false,
                },
            ]);

            await hhLeverageX.initializeGroupLiquidationParams([
                {
                    maxLiqSpreadP: 500000000,
                    startLiqThresholdP: 900000000000,
                    endLiqThresholdP: 750000000000,
                    startLeverage: 2000,
                    endLeverage: 20000,
                },
            ]);

            await hhLeverageX.initializeFeeTiers(
                [0],
                [8000],
                [0, 1],
                [
                    { feeMultiplier: 975, pointsThreshold: 6000000 },
                    { feeMultiplier: 925, pointsThreshold: 50000000 },
                ],
            );

            await hhLeverageX.initializeTradingStorage(
                erc20Token, //rewardsToken
                rewardsDistributor.target, //rewardsDistributor
                1000, //_max_pnl_p bps
                [javBorrowingProvider.target, javBorrowingProvider.target], //borrowingProvider
                [erc20Token, erc20Token2], //collaterals
                [0, 1], //collateralsIndexes
            );

            await hhLeverageX.initializePriceAggregator(
                javPriceAggregator.target,
                javPriceAggregator.target, //alternative oracle
                RANDOM_HASH,
                [0, 1],
                [TOKEN1_PRICE_ID, TOKEN2_PRICE_ID],
            );

            await setPricesForJavPriceAggregator();

            await hhLeverageX.setBorrowingGroupParams(0, 1, {
                feePerBlock: 147,
                maxOi: 253380000000,
                feeExponent: 1,
            });

            await hhLeverageX.setBorrowingGroupParams(1, 1, {
                feePerBlock: 147,
                maxOi: 253380000000,
                feeExponent: 1,
            });

            await hhLeverageX.setBorrowingPairParams(0, 0, {
                groupIndex: 1,
                feePerBlock: BORROWING_PAIR_FEE_PER_BLOCK,
                feeExponent: 1,
                maxOi: BORROWING_PAIR_MAX_OI,
            });

            await hhLeverageX.setBorrowingPairParams(1, 0, {
                groupIndex: 1,
                feePerBlock: BORROWING_PAIR_FEE_PER_BLOCK,
                feeExponent: 1,
                maxOi: BORROWING_PAIR_MAX_OI,
            });

            await hhLeverageX.setBorrowingPairParams(0, 1, {
                groupIndex: 1,
                feePerBlock: BORROWING_PAIR_FEE_PER_BLOCK,
                feeExponent: 1,
                maxOi: BORROWING_PAIR_MAX_OI,
            });

            await hhLeverageX.setBorrowingPairParams(1, 1, {
                groupIndex: 1,
                feePerBlock: BORROWING_PAIR_FEE_PER_BLOCK,
                feeExponent: 1,
                maxOi: BORROWING_PAIR_MAX_OI,
            });

            await hhLeverageX.setPairDepths(
                [0, 1],
                [PAIR_DEPTH_ABOVE_USD, PAIR_DEPTH_ABOVE_USD],
                [PAIR_DEPTH_BELOW_USD, PAIR_DEPTH_BELOW_USD],
            );

            await hhLeverageX.setPriceLifetime(2n ** 48n - 1n);

            await hhLeverageX.updateTradingActivated(0);

            await hhLeverageX.setNegPnlCumulVolMultiplier(P_10);

            await termsAndConditions.connect(trader1).agreeToTerms();
            await termsAndConditions.connect(trader2).agreeToTerms();
        });
    });
    describe("Trades Interactions", () => {
        describe("Shorts", () => {
            describe("Market Order", () => {
                it("Should open trade", async () => {
                    const expectedTraderAddress = trader1.address;
                    const expectedPairIndex = 1;
                    const expectedLeverage = 2000n;
                    const expectedIsLong = false;
                    const expectedIsOpen = true;
                    const expectedCollateralIndex = 0;
                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );
                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        expectedLeverage,
                        expectedIsLong,
                        currentPricePair2,
                    );
                    const expectedTp = parseUnits("8", 9);
                    const expectedSl = parseUnits("12", 9);

                    const expectedTradeIndex = await openTradeWithExpect(
                        trader1,
                        expectedPairIndex,
                        expectedLeverage,
                        expectedIsLong,
                        expectedIsOpen,
                        expectedCollateralIndex,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair2,
                        expectedTp,
                        expectedSl,
                        "MarketExecuted",
                    );

                    const [
                        traderAddress,
                        ,
                        pairIndex,
                        leverage,
                        isLong,
                        isOpen,
                        collateralIndex,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        tp,
                        sl,
                    ] = await hhLeverageX.getTrade(trader1, expectedTradeIndex);

                    expect(traderAddress).to.be.equal(expectedTraderAddress);
                    expect(pairIndex).to.be.equal(expectedPairIndex);
                    expect(leverage).to.be.equal(expectedLeverage);
                    expect(isLong).to.be.equal(expectedIsLong);
                    expect(isOpen).to.be.equal(expectedIsOpen);
                    expect(collateralIndex).to.be.equal(expectedCollateralIndex);
                    expect(tradeType).to.be.equal(TRADE_TYPE_TRADE);
                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                    expect(tp).to.be.equal(expectedTp);
                    expect(sl).to.be.equal(expectedSl);
                });

                it("Should update TP decrease", async () => {
                    const expectedNewTp = parseUnits("6", 9);
                    const tradeIndex = await updateTpWithExpect(
                        trader1,
                        expectedNewTp,
                        "TradeTpUpdated",
                    );

                    const [, , , , , , , , , , tp, ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(tp).to.be.equal(expectedNewTp);
                });

                it("Should update TP increase", async () => {
                    const expectedNewTp = parseUnits("8", 9);
                    const tradeIndex = await updateTpWithExpect(
                        trader1,
                        expectedNewTp,
                        "TradeTpUpdated",
                    );

                    const [, , , , , , , , , , tp, ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(tp).to.be.equal(expectedNewTp);
                });

                it("Should update SL increase", async () => {
                    const [, , , leverage, isLong, , , , , openPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const inputNewSl = parseUnits("14", 9);
                    const expectedNewSl = await limitNewSl(
                        0,
                        inputNewSl,
                        openPrice,
                        leverage,
                        isLong,
                    );

                    const tradeIndex = await updateSlWithExpect(
                        trader1,
                        inputNewSl,
                        "TradeSlUpdated",
                    );

                    const [, , , , , , , , , , , sl] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(sl).to.be.equal(expectedNewSl);
                });

                it("Should update SL decrease", async () => {
                    const expectedNewSl = parseUnits("12", 9);
                    const tradeIndex = await updateSlWithExpect(
                        trader1,
                        expectedNewSl,
                        "TradeSlUpdated",
                    );

                    const [, , , , , , , , , , , sl] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(sl).to.be.equal(expectedNewSl);
                });

                it("Should update leverage increase", async () => {
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);

                    const [, , , oldLeverage, , , , , oldCollateralAmount, , , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const expectedNewLeverage = 2500n;
                    const expectedCollateralAmount = getCollateralAmountLeverageUpdate(
                        oldCollateralAmount,
                        oldLeverage,
                        expectedNewLeverage,
                    );
                    const collateralDelta = oldCollateralAmount - expectedCollateralAmount;

                    const tradeIndex = updateLeverageWithExpect(
                        trader1,
                        expectedNewLeverage,
                        "LeverageUpdateExecuted",
                    );

                    const [, , , leverage, , , , , collateralAmount, , , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(leverage).to.be.equal(expectedNewLeverage);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(collateralDelta);
                });

                it("Should update leverage decrease", async () => {
                    const [, , , oldLeverage, , , , , oldCollateralAmount, , , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const expectedNewLeverage = 2000n;
                    const expectedCollateralAmount = getCollateralAmountLeverageUpdate(
                        oldCollateralAmount,
                        oldLeverage,
                        expectedNewLeverage,
                    );
                    const collateralDelta = expectedCollateralAmount - oldCollateralAmount;

                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(collateralDelta);

                    await erc20Token.connect(trader1).approve(hhLeverageX.target, collateralDelta);

                    const tradeIndex = updateLeverageWithExpect(
                        trader1,
                        expectedNewLeverage,
                        "LeverageUpdateExecuted",
                    );

                    const [, , , leverage, , , , , collateralAmount, , , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(leverage).to.be.equal(expectedNewLeverage);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);
                });

                it("Should increasePositionSize collateral increase", async () => {
                    const [, , , leverage, isLong, , , , oldCollateralAmount, oldOpenPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    [, , , , , , lastPosIncreaseBlockBefore] = await hhLeverageX.getTradeInfo(
                        trader1,
                        traders_trades_counters[trader1.address],
                    );

                    const expectedNewOpenPrice = getOpenPriceCollateralChange(
                        oldCollateralAmount,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        leverage,
                        currentPricePair2,
                        oldOpenPrice,
                        isLong,
                    );

                    const tradeIndex = await increasePositionSizeWithExpect(
                        trader1,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        leverage,
                        currentPricePair2,
                        "PositionSizeIncreaseExecuted",
                    );

                    const [, , , , , , , , newCollateralAmount, newOpenPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    accPairOiShort +=
                        ((newCollateralAmount - oldCollateralAmount) * leverage) / P_3;

                    [, , , , , , lastPosIncreaseBlockAfter] = await hhLeverageX.getTradeInfo(
                        trader1,
                        tradeIndex,
                    );

                    const borrowingBlocksCount =
                        lastPosIncreaseBlockAfter - lastPosIncreaseBlockBefore;

                    const borrowingFeeCollateral = getBorrowingFeeCollateral(
                        borrowingBlocksCount,
                        oldCollateralAmount,
                        leverage,
                    );
                    const totalTradeFeesCollateral = getTotalTradeBaseFees();

                    const expectedCollateralAmount =
                        oldCollateralAmount +
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT -
                        (borrowingFeeCollateral + totalTradeFeesCollateral);

                    expect(newCollateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(newOpenPrice).to.be.equal(expectedNewOpenPrice);
                });

                it("Should decreasePositionSize collateral decrease", async () => {
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);

                    const [, , , feeLastUpdatedBlockBeforeTrade] =
                        await hhLeverageX.getBorrowingPair(0, 1);

                    const [, , , leverage, isLong, , , , oldCollateralAmount, oldOpenPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const expectedNewCollateralAmount =
                        oldCollateralAmount - TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT;

                    const tradeIndex = await decreasePositionSizeWithExpect(
                        trader1,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        0,
                        "PositionSizeDecreaseExecuted",
                    );

                    const [, , , , , , , , newCollateralAmount, newOpenPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    const [, , , feeLastUpdatedBlockAfterTrade] =
                        await hhLeverageX.getBorrowingPair(0, 1);

                    const borrowingBlocksCount =
                        feeLastUpdatedBlockAfterTrade - feeLastUpdatedBlockBeforeTrade;

                    const borrowingFeeCollateral = getBorrowingFeeCollateral(
                        borrowingBlocksCount,
                        oldCollateralAmount,
                        leverage,
                    );

                    const totalTradeFeesCollateral = getTotalTradeBaseFees();

                    const partialTradePnlCollateral = getPartialTradePnlCollateral(
                        oldCollateralAmount,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        leverage,
                        currentPricePair2,
                        oldOpenPrice,
                        isLong,
                    );

                    const expectedCollateralSendToTrader =
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT +
                        partialTradePnlCollateral -
                        (borrowingFeeCollateral + totalTradeFeesCollateral);

                    expect(newCollateralAmount).to.be.equal(expectedNewCollateralAmount);
                    expect(newOpenPrice).to.be.equal(oldOpenPrice);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(
                        expectedCollateralSendToTrader,
                    );
                });

                it("Should close trade", async () => {
                    const traderBalanceBeforeClose = await erc20Token.balanceOf(trader1);

                    const expectedOpenStatus = false;

                    const [, , , leverage, isLong, , , , collateralAmount, oldOpenPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const profitP = getPnlP(currentPricePair2, oldOpenPrice, leverage, isLong);
                    const expectedTradeValueCollateral = getTradePureValue(
                        profitP,
                        collateralAmount,
                        leverage,
                        1n,
                    );

                    const tradeIndex = closeTradeMarketWithExpect(trader1, "TradeClosed");

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(expectedOpenStatus);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(
                        traderBalanceBeforeClose + expectedTradeValueCollateral,
                    );
                });
            });

            describe("Limit order", () => {
                it("Should open trade", async () => {
                    const expectedTraderAddress = trader2.address;
                    const expectedPairIndex = 1;
                    const expectedLeverage = 2000n;
                    const expectedIsLong = false;
                    const expectedIsOpen = true;
                    const expectedCollateralIndex = 0;

                    const expectedTp = parseUnits("8", 9);
                    const expectedSl = parseUnits("12", 9);
                    const expectedOpenPrice = parseUnits("9", 9);

                    const expectedTradeIndex = await openTradeWithExpect(
                        trader2,
                        expectedPairIndex,
                        expectedLeverage,
                        expectedIsLong,
                        expectedIsOpen,
                        expectedCollateralIndex,
                        TRADE_TYPE_LIMIT,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        expectedOpenPrice,
                        expectedTp,
                        expectedSl,
                        "OpenOrderPlaced",
                    );

                    const [
                        traderAddress,
                        ,
                        pairIndex,
                        leverage,
                        isLong,
                        isOpen,
                        collateralIndex,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        tp,
                        sl,
                    ] = await hhLeverageX.getTrade(trader2, expectedTradeIndex);

                    expect(traderAddress).to.be.equal(expectedTraderAddress);
                    expect(pairIndex).to.be.equal(expectedPairIndex);
                    expect(leverage).to.be.equal(expectedLeverage);
                    expect(isLong).to.be.equal(expectedIsLong);
                    expect(isOpen).to.be.equal(expectedIsOpen);
                    expect(collateralIndex).to.be.equal(expectedCollateralIndex);
                    expect(tradeType).to.be.equal(TRADE_TYPE_LIMIT);
                    expect(collateralAmount).to.be.equal(TRADE_INPUT_COLLATERAL_AMOUNT);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                    expect(tp).to.be.equal(expectedTp);
                    expect(sl).to.be.equal(expectedSl);
                });

                it("Should trigger order limit open", async () => {
                    const expectedTradeType = TRADE_TYPE_TRADE;
                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await triggerOrderWithExpect(
                        trader2,
                        TRIGGER_TYPE_LIMIT_OPEN,
                        "LimitExecuted",
                    );

                    const [
                        ,
                        ,
                        ,
                        leverage,
                        isLong,
                        ,
                        ,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        ,
                        ,
                    ] = await hhLeverageX.getTrade(trader2, tradeIndex);

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        leverage,
                        isLong,
                        currentPricePair2,
                    );

                    accPairOiShort += (collateralAmount * leverage) / P_3;

                    expect(tradeType).to.be.equal(expectedTradeType);
                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                });
            });

            describe("Stop Order", () => {
                it("Should open trade", async () => {
                    const expectedTraderAddress = trader2.address;
                    const expectedPairIndex = 1;
                    const expectedLeverage = 2000n;
                    const expectedIsLong = false;
                    const expectedIsOpen = true;
                    const expectedCollateralIndex = 0;

                    const expectedTp = parseUnits("8", 9);
                    const expectedSl = parseUnits("12", 9);
                    const expectedOpenPrice = currentPricePair2;

                    const expectedTradeIndex = await openTradeWithExpect(
                        trader2,
                        expectedPairIndex,
                        expectedLeverage,
                        expectedIsLong,
                        expectedIsOpen,
                        expectedCollateralIndex,
                        TRADE_TYPE_STOP,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        expectedOpenPrice,
                        expectedTp,
                        expectedSl,
                        "OpenOrderPlaced",
                    );

                    const [
                        traderAddress,
                        ,
                        pairIndex,
                        leverage,
                        isLong,
                        isOpen,
                        collateralIndex,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        tp,
                        sl,
                    ] = await hhLeverageX.getTrade(trader2, expectedTradeIndex);

                    expect(traderAddress).to.be.equal(expectedTraderAddress);
                    expect(pairIndex).to.be.equal(expectedPairIndex);
                    expect(leverage).to.be.equal(expectedLeverage);
                    expect(isLong).to.be.equal(expectedIsLong);
                    expect(isOpen).to.be.equal(expectedIsOpen);
                    expect(collateralIndex).to.be.equal(expectedCollateralIndex);
                    expect(tradeType).to.be.equal(TRADE_TYPE_STOP);
                    expect(collateralAmount).to.be.equal(TRADE_INPUT_COLLATERAL_AMOUNT);
                    expect(openPrice).to.be.equal(currentPricePair2);
                    expect(tp).to.be.equal(expectedTp);
                    expect(sl).to.be.equal(expectedSl);
                });

                it("Should trigger order stop open", async () => {
                    const expectedTradeType = TRADE_TYPE_TRADE;
                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await triggerOrderWithExpect(
                        trader2,
                        TRIGGER_TYPE_STOP_OPEN,
                        "LimitExecuted",
                    );

                    const [
                        ,
                        ,
                        ,
                        leverage,
                        isLong,
                        ,
                        ,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        ,
                        ,
                    ] = await hhLeverageX.getTrade(trader2, tradeIndex);

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        leverage,
                        isLong,
                        currentPricePair1,
                    );

                    accPairOiShort += (collateralAmount * leverage) / P_3;

                    expect(tradeType).to.be.equal(expectedTradeType);
                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                });
            });

            describe("Order Trigger Closings", () => {
                it("Should trigger order close TP", async () => {
                    await ethers.provider.send("evm_mine"); //for symmetry of blocks number

                    const [, , , feeLastUpdatedBlockBeforeTrade] =
                        await hhLeverageX.getBorrowingPair(0, 1);

                    const inputTp = parseUnits("8", 9);
                    const inputSl = parseUnits("12", 9);
                    const inputIsLong = false;
                    const inputLeverage = 2000n;

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        inputLeverage,
                        inputIsLong,
                        currentPricePair2,
                    );

                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await openTradeWithExpect(
                        trader1,
                        1,
                        inputLeverage,
                        inputIsLong,
                        true,
                        0,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair2,
                        inputTp,
                        inputSl,
                        "MarketExecuted",
                    );

                    const [, , , leverage, isLong, , , , collateralAmount, openPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);

                    await updatePriceFeed(inputTp, PAIR2_PRICE_ID, owner);

                    await triggerOrderWithExpect(trader1, TRIGGER_TYPE_TP_CLOSE, "LimitExecuted");

                    const [, , , feeLastUpdatedBlockAfterTrade] =
                        await hhLeverageX.getBorrowingPair(0, 1);

                    const borrowingBlocksCount =
                        feeLastUpdatedBlockAfterTrade - feeLastUpdatedBlockBeforeTrade - 1n;

                    const profitP = getPnlP(inputTp, expectedOpenPrice, leverage, isLong);

                    const tradeValueCollateral = getTradePureValue(
                        profitP,
                        expectedCollateralAmount,
                        leverage,
                        borrowingBlocksCount,
                    );

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(false);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(tradeValueCollateral);
                });

                it("Should trigger order close SL", async () => {
                    await updatePriceFeed(currentPricePair2, PAIR2_PRICE_ID, signer1);

                    const [, , , feeLastUpdatedBlockBeforeTrade] =
                        await hhLeverageX.getBorrowingPair(0, 1);

                    const inputTp = parseUnits("8", 9);
                    const inputSl = parseUnits("12", 9);
                    const inputIsLong = false;
                    const inputLeverage = 2000n;

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        inputLeverage,
                        inputIsLong,
                        currentPricePair1,
                    );

                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await openTradeWithExpect(
                        trader1,
                        1,
                        inputLeverage,
                        inputIsLong,
                        true,
                        0,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair2,
                        inputTp,
                        inputSl,
                        "MarketExecuted",
                    );

                    const [, , , leverage, isLong, , , , collateralAmount, openPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);

                    await updatePriceFeed(inputSl, PAIR2_PRICE_ID, owner);

                    await triggerOrderWithExpect(trader1, TRIGGER_TYPE_SL_CLOSE, "LimitExecuted");

                    const [, , , feeLastUpdatedBlockAfterTrade] =
                        await hhLeverageX.getBorrowingPair(0, 1);

                    const borrowingBlocksCount =
                        feeLastUpdatedBlockAfterTrade - feeLastUpdatedBlockBeforeTrade - 1n;

                    const profitP = getPnlP(inputSl, expectedOpenPrice, leverage, isLong);

                    const tradeValueCollateral = getTradePureValue(
                        profitP,
                        expectedCollateralAmount,
                        leverage,
                        borrowingBlocksCount,
                    );

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(false);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(tradeValueCollateral);
                });

                it("Should trigger order close LIQ", async () => {
                    await updatePriceFeed(currentPricePair2, PAIR2_PRICE_ID, signer2);

                    const inputLiq = parseUnits("12", 9);

                    const inputTp = parseUnits("8", 9);
                    const inputSl = parseUnits("13", 9);
                    const inputIsLong = false;
                    const inputLeverage = 5000n;

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        inputLeverage,
                        inputIsLong,
                        currentPricePair2,
                    );

                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await openTradeWithExpect(
                        trader1,
                        1,
                        inputLeverage,
                        inputIsLong,
                        true,
                        0,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair2,
                        inputTp,
                        inputSl,
                        "MarketExecuted",
                    );

                    const [, , , leverage, isLong, , , , collateralAmount, openPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);

                    await updatePriceFeed(inputLiq, PAIR2_PRICE_ID, signer3);

                    await triggerOrderWithExpect(trader1, TRIGGER_TYPE_LIQ_CLOSE, "LimitExecuted");

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(false);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);
                });
            });
        });

        describe("Longs", () => {
            describe("Market Order", () => {
                it("Should open trade", async () => {
                    const expectedTraderAddress = trader1.address;
                    const expectedPairIndex = 0;
                    const expectedLeverage = 2000n;
                    const expectedIsLong = true;
                    const expectedIsOpen = true;
                    const expectedCollateralIndex = 0;
                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );
                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        expectedLeverage,
                        expectedIsLong,
                        currentPricePair1,
                    );
                    const expectedTp = parseUnits("12", 9);
                    const expectedSl = parseUnits("8", 9);

                    const expectedTradeIndex = await openTradeWithExpect(
                        trader1,
                        expectedPairIndex,
                        expectedLeverage,
                        expectedIsLong,
                        expectedIsOpen,
                        expectedCollateralIndex,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair1,
                        expectedTp,
                        expectedSl,
                        "MarketExecuted",
                    );

                    const [
                        traderAddress,
                        ,
                        pairIndex,
                        leverage,
                        isLong,
                        isOpen,
                        collateralIndex,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        tp,
                        sl,
                    ] = await hhLeverageX.getTrade(trader1, expectedTradeIndex);

                    expect(traderAddress).to.be.equal(expectedTraderAddress);
                    expect(pairIndex).to.be.equal(expectedPairIndex);
                    expect(leverage).to.be.equal(expectedLeverage);
                    expect(isLong).to.be.equal(expectedIsLong);
                    expect(isOpen).to.be.equal(expectedIsOpen);
                    expect(collateralIndex).to.be.equal(expectedCollateralIndex);
                    expect(tradeType).to.be.equal(TRADE_TYPE_TRADE);
                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                    expect(tp).to.be.equal(expectedTp);
                    expect(sl).to.be.equal(expectedSl);
                });

                it("Should update TP increase", async () => {
                    const expectedNewTp = parseUnits("14", 9);
                    const tradeIndex = await updateTpWithExpect(
                        trader1,
                        expectedNewTp,
                        "TradeTpUpdated",
                    );

                    const [, , , , , , , , , , tp, ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(tp).to.be.equal(expectedNewTp);
                });

                it("Should update TP decrease", async () => {
                    const expectedNewTp = parseUnits("12", 9);
                    const tradeIndex = await updateTpWithExpect(
                        trader1,
                        expectedNewTp,
                        "TradeTpUpdated",
                    );

                    const [, , , , , , , , , , tp, ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(tp).to.be.equal(expectedNewTp);
                });

                it("Should update SL increase", async () => {
                    const expectedNewSl = parseUnits("9", 9);
                    const tradeIndex = await updateSlWithExpect(
                        trader1,
                        expectedNewSl,
                        "TradeSlUpdated",
                    );

                    const [, , , , , , , , , , , sl] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(sl).to.be.equal(expectedNewSl);
                });

                it("Should update SL decrease", async () => {
                    const expectedNewSl = parseUnits("7", 9);
                    const tradeIndex = await updateSlWithExpect(
                        trader1,
                        expectedNewSl,
                        "TradeSlUpdated",
                    );

                    const [, , , , , , , , , , , sl] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(sl).to.be.equal(expectedNewSl);
                });

                it("Should update leverage increase", async () => {
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);

                    const [, , , oldLeverage, , , , , oldCollateralAmount, , , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const expectedNewLeverage = 2500n;
                    const expectedCollateralAmount = getCollateralAmountLeverageUpdate(
                        oldCollateralAmount,
                        oldLeverage,
                        expectedNewLeverage,
                    );
                    const collateralDelta = oldCollateralAmount - expectedCollateralAmount;

                    const tradeIndex = updateLeverageWithExpect(
                        trader1,
                        expectedNewLeverage,
                        "LeverageUpdateExecuted",
                    );

                    const [, , , leverage, , , , , collateralAmount, , , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(leverage).to.be.equal(expectedNewLeverage);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(collateralDelta);
                });

                it("Should update leverage decrease", async () => {
                    const [, , , oldLeverage, , , , , oldCollateralAmount, , , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const expectedNewLeverage = 2000n;
                    const expectedCollateralAmount = getCollateralAmountLeverageUpdate(
                        oldCollateralAmount,
                        oldLeverage,
                        expectedNewLeverage,
                    );
                    const collateralDelta = expectedCollateralAmount - oldCollateralAmount;

                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(collateralDelta);

                    await erc20Token.connect(trader1).approve(hhLeverageX.target, collateralDelta);

                    const tradeIndex = updateLeverageWithExpect(
                        trader1,
                        expectedNewLeverage,
                        "LeverageUpdateExecuted",
                    );

                    const [, , , leverage, , , , , collateralAmount, , , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(leverage).to.be.equal(expectedNewLeverage);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);
                });

                it("Should increasePositionSize collateral increase", async () => {
                    const [, , , leverage, isLong, , , , oldCollateralAmount, oldOpenPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    [, , , , , , lastPosIncreaseBlockBefore] = await hhLeverageX.getTradeInfo(
                        trader1,
                        traders_trades_counters[trader1.address],
                    );

                    const expectedNewOpenPrice = getOpenPriceCollateralChange(
                        oldCollateralAmount,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        leverage,
                        currentPricePair1,
                        oldOpenPrice,
                        isLong,
                    );

                    const tradeIndex = await increasePositionSizeWithExpect(
                        trader1,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        leverage,
                        currentPricePair1,
                        "PositionSizeIncreaseExecuted",
                    );

                    const [, , , , , , , , newCollateralAmount, newOpenPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    accPairOiLong += ((newCollateralAmount - oldCollateralAmount) * leverage) / P_3;

                    [, , , , , , lastPosIncreaseBlockAfter] = await hhLeverageX.getTradeInfo(
                        trader1,
                        tradeIndex,
                    );

                    const borrowingBlocksCount =
                        lastPosIncreaseBlockAfter - lastPosIncreaseBlockBefore;

                    const borrowingFeeCollateral = getBorrowingFeeCollateral(
                        borrowingBlocksCount,
                        oldCollateralAmount,
                        leverage,
                    );
                    const totalTradeFeesCollateral = getTotalTradeBaseFees();

                    const expectedCollateralAmount =
                        oldCollateralAmount +
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT -
                        (borrowingFeeCollateral + totalTradeFeesCollateral);

                    expect(newCollateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(newOpenPrice).to.be.equal(expectedNewOpenPrice);
                });

                it("Should decreasePositionSize collateral decrease", async () => {
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);

                    const [, , , feeLastUpdatedBlockBeforeTrade] =
                        await hhLeverageX.getBorrowingPair(0, 0);

                    const [, , , leverage, isLong, , , , oldCollateralAmount, oldOpenPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const expectedNewCollateralAmount =
                        oldCollateralAmount - TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT;

                    const tradeIndex = await decreasePositionSizeWithExpect(
                        trader1,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        0,
                        "PositionSizeDecreaseExecuted",
                    );

                    const [, , , , , , , , newCollateralAmount, newOpenPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    const [, , , feeLastUpdatedBlockAfterTrade] =
                        await hhLeverageX.getBorrowingPair(0, 0);

                    const borrowingBlocksCount =
                        feeLastUpdatedBlockAfterTrade - feeLastUpdatedBlockBeforeTrade;

                    const borrowingFeeCollateral = getBorrowingFeeCollateral(
                        borrowingBlocksCount,
                        oldCollateralAmount,
                        leverage,
                    );

                    const totalTradeFeesCollateral = getTotalTradeBaseFees();

                    const partialTradePnlCollateral = getPartialTradePnlCollateral(
                        oldCollateralAmount,
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT,
                        leverage,
                        currentPricePair1,
                        oldOpenPrice,
                        isLong,
                    );

                    const expectedCollateralSendToTrader =
                        TRADE_CHANGE_COLLATERAL_INPUT_AMOUNT +
                        partialTradePnlCollateral -
                        (borrowingFeeCollateral + totalTradeFeesCollateral);

                    expect(newCollateralAmount).to.be.equal(expectedNewCollateralAmount);
                    expect(newOpenPrice).to.be.equal(oldOpenPrice);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(
                        expectedCollateralSendToTrader,
                    );
                });

                it("Should close trade", async () => {
                    const traderBalanceBeforeClose = await erc20Token.balanceOf(trader1);

                    const expectedOpenStatus = false;

                    const [, , , leverage, isLong, , , , collateralAmount, oldOpenPrice, , ,] =
                        await hhLeverageX.getTrade(
                            trader1,
                            traders_trades_counters[trader1.address],
                        );

                    const profitP = getPnlP(currentPricePair1, oldOpenPrice, leverage, isLong);
                    const expectedTradeValueCollateral = getTradePureValue(
                        profitP,
                        collateralAmount,
                        leverage,
                        1n,
                    );

                    const tradeIndex = closeTradeMarketWithExpect(trader1, "TradeClosed");

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(expectedOpenStatus);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(
                        traderBalanceBeforeClose + expectedTradeValueCollateral,
                    );
                });
            });
            describe("Limit order", () => {
                it("Should open trade", async () => {
                    const expectedTraderAddress = trader2.address;
                    const expectedPairIndex = 0;
                    const expectedLeverage = 2000n;
                    const expectedIsLong = true;
                    const expectedIsOpen = true;
                    const expectedCollateralIndex = 0;

                    const expectedTp = parseUnits("12", 9);
                    const expectedSl = parseUnits("8", 9);

                    const expectedTradeIndex = await openTradeWithExpect(
                        trader2,
                        expectedPairIndex,
                        expectedLeverage,
                        expectedIsLong,
                        expectedIsOpen,
                        expectedCollateralIndex,
                        TRADE_TYPE_LIMIT,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair1,
                        expectedTp,
                        expectedSl,
                        "OpenOrderPlaced",
                    );

                    const [
                        traderAddress,
                        ,
                        pairIndex,
                        leverage,
                        isLong,
                        isOpen,
                        collateralIndex,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        tp,
                        sl,
                    ] = await hhLeverageX.getTrade(trader2, expectedTradeIndex);

                    expect(traderAddress).to.be.equal(expectedTraderAddress);
                    expect(pairIndex).to.be.equal(expectedPairIndex);
                    expect(leverage).to.be.equal(expectedLeverage);
                    expect(isLong).to.be.equal(expectedIsLong);
                    expect(isOpen).to.be.equal(expectedIsOpen);
                    expect(collateralIndex).to.be.equal(expectedCollateralIndex);
                    expect(tradeType).to.be.equal(TRADE_TYPE_LIMIT);
                    expect(collateralAmount).to.be.equal(TRADE_INPUT_COLLATERAL_AMOUNT);
                    expect(openPrice).to.be.equal(currentPricePair1);
                    expect(tp).to.be.equal(expectedTp);
                    expect(sl).to.be.equal(expectedSl);
                });

                it("Should trigger order limit open", async () => {
                    const expectedTradeType = TRADE_TYPE_TRADE;
                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await triggerOrderWithExpect(
                        trader2,
                        TRIGGER_TYPE_LIMIT_OPEN,
                        "LimitExecuted",
                    );

                    const [
                        ,
                        ,
                        ,
                        leverage,
                        isLong,
                        ,
                        ,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        ,
                        ,
                    ] = await hhLeverageX.getTrade(trader2, tradeIndex);

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        leverage,
                        isLong,
                        currentPricePair1,
                    );

                    accPairOiLong += (collateralAmount * leverage) / P_3;

                    expect(tradeType).to.be.equal(expectedTradeType);
                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                });
            });

            describe("Stop Order", () => {
                it("Should open trade", async () => {
                    const expectedTraderAddress = trader2.address;
                    const expectedPairIndex = 0;
                    const expectedLeverage = 2000n;
                    const expectedIsLong = true;
                    const expectedIsOpen = true;
                    const expectedCollateralIndex = 0;

                    const expectedTp = parseUnits("12", 9);
                    const expectedSl = parseUnits("8", 9);

                    const expectedTradeIndex = await openTradeWithExpect(
                        trader2,
                        expectedPairIndex,
                        expectedLeverage,
                        expectedIsLong,
                        expectedIsOpen,
                        expectedCollateralIndex,
                        TRADE_TYPE_STOP,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair1,
                        expectedTp,
                        expectedSl,
                        "OpenOrderPlaced",
                    );

                    const [
                        traderAddress,
                        ,
                        pairIndex,
                        leverage,
                        isLong,
                        isOpen,
                        collateralIndex,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        tp,
                        sl,
                    ] = await hhLeverageX.getTrade(trader2, expectedTradeIndex);

                    expect(traderAddress).to.be.equal(expectedTraderAddress);
                    expect(pairIndex).to.be.equal(expectedPairIndex);
                    expect(leverage).to.be.equal(expectedLeverage);
                    expect(isLong).to.be.equal(expectedIsLong);
                    expect(isOpen).to.be.equal(expectedIsOpen);
                    expect(collateralIndex).to.be.equal(expectedCollateralIndex);
                    expect(tradeType).to.be.equal(TRADE_TYPE_STOP);
                    expect(collateralAmount).to.be.equal(TRADE_INPUT_COLLATERAL_AMOUNT);
                    expect(openPrice).to.be.equal(currentPricePair1);
                    expect(tp).to.be.equal(expectedTp);
                    expect(sl).to.be.equal(expectedSl);
                });

                it("Should trigger order stop open", async () => {
                    const expectedTradeType = TRADE_TYPE_TRADE;
                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await triggerOrderWithExpect(
                        trader2,
                        TRIGGER_TYPE_STOP_OPEN,
                        "LimitExecuted",
                    );

                    const [
                        ,
                        ,
                        ,
                        leverage,
                        isLong,
                        ,
                        ,
                        tradeType,
                        collateralAmount,
                        openPrice,
                        ,
                        ,
                    ] = await hhLeverageX.getTrade(trader2, tradeIndex);

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        leverage,
                        isLong,
                        currentPricePair1,
                    );

                    accPairOiLong += (collateralAmount * leverage) / P_3;

                    expect(tradeType).to.be.equal(expectedTradeType);
                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);
                });
            });

            describe("Order Trigger Closings", () => {
                it("Should trigger order close TP", async () => {
                    await ethers.provider.send("evm_mine"); //for symmetry of blocks number

                    const [, , , feeLastUpdatedBlockBeforeTrade] =
                        await hhLeverageX.getBorrowingPair(0, 0);

                    const inputTp = parseUnits("12", 9);
                    const inputSl = parseUnits("8", 9);
                    const inputIsLong = true;
                    const inputLeverage = 2000n;

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        inputLeverage,
                        inputIsLong,
                        currentPricePair1,
                    );

                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await openTradeWithExpect(
                        trader1,
                        0,
                        inputLeverage,
                        inputIsLong,
                        true,
                        0,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair1,
                        inputTp,
                        inputSl,
                        "MarketExecuted",
                    );

                    const [, , , leverage, isLong, , , , collateralAmount, openPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);

                    await updatePriceFeed(inputTp, PAIR1_PRICE_ID, owner);

                    await triggerOrderWithExpect(trader1, TRIGGER_TYPE_TP_CLOSE, "LimitExecuted");

                    const [, , , feeLastUpdatedBlockAfterTrade] =
                        await hhLeverageX.getBorrowingPair(0, 0);

                    const borrowingBlocksCount =
                        feeLastUpdatedBlockAfterTrade - feeLastUpdatedBlockBeforeTrade - 1n;

                    const profitP = getPnlP(inputTp, expectedOpenPrice, leverage, isLong);

                    const tradeValueCollateral = getTradePureValue(
                        profitP,
                        expectedCollateralAmount,
                        leverage,
                        borrowingBlocksCount,
                    );

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(false);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(tradeValueCollateral);
                });

                it("Should trigger order close SL", async () => {
                    await updatePriceFeed(currentPricePair1, PAIR1_PRICE_ID, signer1);

                    const [, , , feeLastUpdatedBlockBeforeTrade] =
                        await hhLeverageX.getBorrowingPair(0, 0);

                    const inputTp = parseUnits("12", 9);
                    const inputSl = parseUnits("8", 9);
                    const inputIsLong = true;
                    const inputLeverage = 2000n;

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        inputLeverage,
                        inputIsLong,
                        currentPricePair1,
                    );

                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await openTradeWithExpect(
                        trader1,
                        0,
                        inputLeverage,
                        inputIsLong,
                        true,
                        0,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair1,
                        inputTp,
                        inputSl,
                        "MarketExecuted",
                    );

                    const [, , , leverage, isLong, , , , collateralAmount, openPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);

                    await updatePriceFeed(inputSl, PAIR1_PRICE_ID, owner);

                    await triggerOrderWithExpect(trader1, TRIGGER_TYPE_SL_CLOSE, "LimitExecuted");

                    const [, , , feeLastUpdatedBlockAfterTrade] =
                        await hhLeverageX.getBorrowingPair(0, 0);

                    const borrowingBlocksCount =
                        feeLastUpdatedBlockAfterTrade - feeLastUpdatedBlockBeforeTrade - 1n;

                    const profitP = getPnlP(inputSl, expectedOpenPrice, leverage, isLong);

                    const tradeValueCollateral = getTradePureValue(
                        profitP,
                        expectedCollateralAmount,
                        leverage,
                        borrowingBlocksCount,
                    );

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(false);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(tradeValueCollateral);
                });

                it("Should trigger order close LIQ", async () => {
                    await updatePriceFeed(currentPricePair1, PAIR1_PRICE_ID, signer2);

                    const inputLiq = parseUnits("8", 9);

                    const inputTp = parseUnits("12", 9);
                    const inputSl = parseUnits("7", 9);
                    const inputIsLong = true;
                    const inputLeverage = 5000n;

                    const expectedOpenPrice = getOpenPriceWithImpact(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        inputLeverage,
                        inputIsLong,
                        currentPricePair1,
                    );

                    const expectedCollateralAmount = getCollateralAmountMinusBaseFees(
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                    );

                    const tradeIndex = await openTradeWithExpect(
                        trader1,
                        0,
                        inputLeverage,
                        inputIsLong,
                        true,
                        0,
                        TRADE_TYPE_TRADE,
                        TRADE_INPUT_COLLATERAL_AMOUNT,
                        currentPricePair1,
                        inputTp,
                        inputSl,
                        "MarketExecuted",
                    );

                    const [, , , leverage, isLong, , , , collateralAmount, openPrice, , ,] =
                        await hhLeverageX.getTrade(trader1, tradeIndex);

                    expect(collateralAmount).to.be.equal(expectedCollateralAmount);
                    expect(openPrice).to.be.equal(expectedOpenPrice);

                    await updatePriceFeed(inputLiq, PAIR1_PRICE_ID, signer3);

                    await triggerOrderWithExpect(trader1, TRIGGER_TYPE_LIQ_CLOSE, "LimitExecuted");

                    const [, , , , , isOpenAfterClose, , , , , , ,] = await hhLeverageX.getTrade(
                        trader1,
                        tradeIndex,
                    );

                    expect(isOpenAfterClose).to.be.equal(false);
                    expect(await erc20Token.balanceOf(trader1)).to.be.equal(0);
                });
            });
        });
    });
});
