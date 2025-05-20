const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const baseArgs = [
        {
            name: "LeverageX JAV",
            symbol: "xJAV"
        }, //  _meta,
        {
            asset: "0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9",
            pnlHandler: "0xBF35e4273db5692777EA475728fDbBa092FFa1B3"
        }, // _contractAddresses,
        ethers.parseEther("1"), // _maxDailyAccPnlDelta,
        ethers.parseEther("50"), // _maxSupplyIncreaseDailyP,
        1742947200, // _commencementTimestamp,
        86400, // _epochDuration,
        3, // _withdrawEpochsLock
        "0x813D8A8120152ff9662F43EEF0d86B6AaBa351f0", //_termsAndConditionsAddress,
        "0xe7E65d1c76293CF2367b6545A763a84d347E3658",// _javInfoAggregator,
        [200, 165, 149, 132, 116, 99, 66, 33], //_baseFees,
        [0, 500, 5000, 10000, 25000, 50000, 100000, 500000], // _usdThresholds,
        [0, 100000, 250000, 500000, 1000000], // _javThresholds,
        [10000, 7500, 5000, 2500, 1250], // _reductionFactors,
        [300, 200, 100, 50, 25] // _sellFees
    ];

    const sepolia_baseArgs = [
        {
            name: "LeverageX JAVLIS",
            symbol: "xJAVLIS"
        }, //  _meta,
        {
            asset: "0x9CF7EFD1376a9142d4C22e1573fB31B1f378DAF6",
            pnlHandler: "0xDED8c59c45D8e0f45D8C32f6F6E0A4a2d582e59d"
        }, // _contractAddresses,
        ethers.parseEther("1"), // _maxDailyAccPnlDelta,
        ethers.parseEther("50"), // _maxSupplyIncreaseDailyP,
        1747699200, // _commencementTimestamp,
        300, // _epochDuration,
        3, // _withdrawEpochsLock
        "0x65483760C32111f6661b4E431FA932d190F53e1e", //_termsAndConditionsAddress,
        "0x978Be6a5bF6827BE7840337F72Bd39db75526Bbc",// _javInfoAggregator,
        [200, 165, 149, 132, 116, 99, 66, 33], //_baseFees,
        [0, 500, 5000, 10000, 25000, 50000, 100000, 500000], // _usdThresholds,
        [0, 100000, 250000, 500000, 1000000], // _javThresholds,
        [10000, 7500, 5000, 2500, 1250], // _reductionFactors,
        [300, 200, 100, 50, 25] // _sellFees
    ];

    const Contract = await ethers.getContractFactory("XVault");
    const contract = await upgrades.deployProxy(Contract, sepolia_baseArgs, {
        initializer: "initialize",
        kind: "uups",
        redeployImplementation: "always",
    });
    await contract.waitForDeployment();

    logDeploy("XVault", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
