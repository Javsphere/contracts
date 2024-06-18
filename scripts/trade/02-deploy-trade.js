const {ethers, upgrades} = require("hardhat");
const {logDeploy} = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const managerAddress = "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb"
    // const managerAddress = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    const multiCollatDiamondFactory = await ethers.getContractFactory("JavMultiCollatDiamond");
    const multiCollatDiamond = await upgrades.deployProxy(
        multiCollatDiamondFactory,
        [
            managerAddress, //_rolesManager
        ],

        {
            initializer: "initialize",
            kind: "uups",
            txOverrides: {
                gasLimit: ethers.parseUnits("0.03", "gwei"),
            },
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

    const priceImpactFactory = await ethers.getContractFactory("JavPriceImpact");
    const priceImpact = await priceImpactFactory.deploy();
    await priceImpact.waitForDeployment();

    logDeploy("JavPriceImpact", await priceImpact.getAddress());

    const tradingStorageFactory = await ethers.getContractFactory("JavTradingStorage");
    const tradingStorage = await tradingStorageFactory.deploy();
    await tradingStorage.waitForDeployment();

    logDeploy("JavTradingStorage", await tradingStorage.getAddress());

    const tradingInteractionsFactory = await ethers.getContractFactory("JavTradingInteractions", {
        libraries: {
            "contracts/libraries/trade/PackingUtils.sol:PackingUtils":
                "0x26F3b46eBf6bEE0Bfe5fE82c8EfD8CA2Fc769bE6",
        },
    });
    const tradingInteractions = await tradingInteractionsFactory.deploy();
    await tradingInteractions.waitForDeployment();

    logDeploy("JavTradingInteractions", await tradingInteractions.getAddress());

    const tradingProcessingFactory = await ethers.getContractFactory("JavTradingProcessing");
    const tradingProcessing = await tradingProcessingFactory.deploy();
    await tradingProcessing.waitForDeployment();

    logDeploy("JavTradingProcessing", await tradingProcessing.getAddress());

    const borrowingFeesFactory = await ethers.getContractFactory("JavBorrowingFees");
    const borrowingFees = await borrowingFeesFactory.deploy();
    await borrowingFees.waitForDeployment();

    logDeploy("JavBorrowingFees", await borrowingFees.getAddress());

    const priceAggregatorFactory = await ethers.getContractFactory(
        "contracts/trade/JavPriceAggregator.sol:JavPriceAggregator",
    );
    const priceAggregator = await priceAggregatorFactory.deploy();
    await priceAggregator.waitForDeployment();

    logDeploy("JavPriceAggregator", await priceAggregator.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
