const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("Vote");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb", // _adminAddress
            "0x85FCe36f585B1E78058B86B6FC57E026050184CF", // _vestingAddress
            "0xf76254B11418960F71750c4E14004eb4Bb96d0C8", // _stakingAddress
            "0x0acFA3C551090D682937aa1bC29B9C8F892E1918", // _freezerAddress
            25, // _stakingFactor
            2000, // _vestingFactor
            [0, 1, 2, 3, 4, 5, 6], // _freezerIdsFactor
            [100, 350, 800, 1750, 3900, 700, 1500], // _freezerFactors
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("Vote", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
