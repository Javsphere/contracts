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
        1e8, // _maxDailyAccPnlDelta,
        ethers.parseEther("50"), // _maxSupplyIncreaseDailyP,
        1742947200, // _commencementTimestamp,
        86400, // _epochDuration,
        3 // _withdrawEpochsLock
    ];

    const sepolia_baseArgs = [
        {
            name: "LeverageX JAV",
            symbol: "xJAV"
        }, //  _meta,
        {
            asset: "0x83030ec707812Af7e71042fA17153E7fC1822573",
            pnlHandler: "0xDED8c59c45D8e0f45D8C32f6F6E0A4a2d582e59d"
        }, // _contractAddresses,
        ethers.parseEther("1"), // _maxDailyAccPnlDelta,
        ethers.parseEther("50"), // _maxSupplyIncreaseDailyP,
        1742947200, // _commencementTimestamp,
        86400, // _epochDuration,
        3 // _withdrawEpochsLock
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
