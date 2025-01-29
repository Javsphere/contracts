const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavInfoAggregator");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x83030ec707812Af7e71042fA17153E7fC1822573", // _javAddress
            "0x0000000000000000000000000000000000000000", // _javPool
            "0x85FCe36f585B1E78058B86B6FC57E026050184CF", // _vestingAddress
            "0xf76254B11418960F71750c4E14004eb4Bb96d0C8", // _stakingAddress
            "0x0acFA3C551090D682937aa1bC29B9C8F892E1918", // _freezerAddress
            "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729", // _priceAggregator

        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavInfoAggregator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
