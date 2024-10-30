const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const PackingUtils = await ethers.getContractFactory("PackingUtils");
    const packlingUtils = await PackingUtils.deploy();

    logDeploy("PackingUtils", packlingUtils.target);

    const ArrayGetters = await ethers.getContractFactory("ArrayGetters");
    const arrayGetters = await ArrayGetters.deploy();

    logDeploy("ArrayGetters", arrayGetters.target);

    const TradingCommonUtils = await ethers.getContractFactory("TradingCommonUtils");
    const tradingCommonUtils = await TradingCommonUtils.deploy();

    logDeploy("TradingCommonUtils", tradingCommonUtils.target);

    const UpdateLeverageUtils = await ethers.getContractFactory("UpdateLeverageUtils", {
        libraries: {
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
        },
    });
    const updateLeverageUtils = await UpdateLeverageUtils.deploy();

    logDeploy("UpdateLeverageUtils", updateLeverageUtils.target);

    const UpdatePositionSizeUtils = await ethers.getContractFactory("UpdatePositionSizeUtils", {
        libraries: {
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
        },
    });
    const updatePositionSizeUtils = await UpdatePositionSizeUtils.deploy();

    logDeploy("UpdatePositionSizeUtils", updatePositionSizeUtils.target);

    const managerAddress = "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb";
    // const managerAddress = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199";

    const multiCollatDiamondFactory = await ethers.getContractFactory("JavMultiCollatDiamond");
    const multiCollatDiamond = await upgrades.deployProxy(
        multiCollatDiamondFactory,
        [
            managerAddress, //_rolesManager
        ],

        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await multiCollatDiamond.waitForDeployment();

    logDeploy("JavMultiCollatDiamond", await multiCollatDiamond.getAddress());

    const pairsStorageFactory = await ethers.getContractFactory("JavPairsStorage");
    const pairsStorage = await pairsStorageFactory.deploy();
    await pairsStorage.waitForDeployment();

    logDeploy("JavPairsStorage", await pairsStorage.getAddress());

    const referralsFactory = await ethers.getContractFactory("JavReferrals");
    const referrals = await referralsFactory.deploy();
    await referrals.waitForDeployment();

    logDeploy("JavReferrals", await referrals.getAddress());

    const feeTiersFactory = await ethers.getContractFactory("JavFeeTiers");
    const feeTiers = await feeTiersFactory.deploy();
    await feeTiers.waitForDeployment();

    logDeploy("JavFeeTiers", await feeTiers.getAddress());

    const priceImpactFactory = await ethers.getContractFactory("JavPriceImpact", {
        libraries: {
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
        },
    });
    const priceImpact = await priceImpactFactory.deploy();
    await priceImpact.waitForDeployment();

    logDeploy("JavPriceImpact", await priceImpact.getAddress());

    const tradingStorageFactory = await ethers.getContractFactory("JavTradingStorage", {
        libraries: {
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
            "contracts/libraries/leverageX/ArrayGetters.sol:ArrayGetters": arrayGetters.target,
        },
    });
    const tradingStorage = await tradingStorageFactory.deploy();
    await tradingStorage.waitForDeployment();

    logDeploy("JavTradingStorage", await tradingStorage.getAddress());

    const tradingInteractionsFactory = await ethers.getContractFactory("JavTradingInteractions", {
        libraries: {
            "contracts/libraries/leverageX/PackingUtils.sol:PackingUtils":
                "0xE438848bb41658a2203a245CA0c7d466e75AEB31",
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
            "contracts/libraries/leverageX/updateLeverage/UpdateLeverageUtils.sol:UpdateLeverageUtils":
                updateLeverageUtils.target,
            "contracts/libraries/leverageX/updatePositionSize/UpdatePositionSizeUtils.sol:UpdatePositionSizeUtils":
                updatePositionSizeUtils.target,
        },
    });
    const tradingInteractions = await tradingInteractionsFactory.deploy();
    await tradingInteractions.waitForDeployment();

    logDeploy("JavTradingInteractions", await tradingInteractions.getAddress());

    const tradingProcessingFactory = await ethers.getContractFactory("JavTradingProcessing", {
        libraries: {
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
        },
    });
    const tradingProcessing = await tradingProcessingFactory.deploy();
    await tradingProcessing.waitForDeployment();

    logDeploy("JavTradingProcessing", await tradingProcessing.getAddress());

    const borrowingFeesFactory = await ethers.getContractFactory("JavBorrowingFees", {
        libraries: {
            "contracts/libraries/leverageX/TradingCommonUtils.sol:TradingCommonUtils":
                tradingCommonUtils.target,
        },
    });
    const borrowingFees = await borrowingFeesFactory.deploy();
    await borrowingFees.waitForDeployment();

    logDeploy("JavBorrowingFees", await borrowingFees.getAddress());

    const priceAggregatorFactory = await ethers.getContractFactory(
        "contracts/leverageX/JavPriceAggregator.sol:JavPriceAggregator",
    );
    const priceAggregator = await priceAggregatorFactory.deploy();
    await priceAggregator.waitForDeployment();

    logDeploy("JavPriceAggregator", await priceAggregator.getAddress());

    // // localhost
    // const tokenFactory = await ethers.getContractFactory("TestToken");
    // const token1 = await tokenFactory.deploy(["Test USDT", "USDT"]);
    // await token1.waitForDeployment();
    //
    // logDeploy("TestUSDT", await token1.getAddress());
    //
    // const token2 = await tokenFactory.deploy(["Test USDT1", "USDT1"]);
    // await token2.waitForDeployment();
    //
    // logDeploy("TestUSDT1", await token2.getAddress());
    //
    // const rewardsCollectorFactory = await ethers.getContractFactory("RewardsCollector");
    // const rewardsCollector = await rewardsCollectorFactory.deploy();
    // await rewardsCollector.waitForDeployment();
    //
    // logDeploy("RewardsCollector", await rewardsCollector.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
