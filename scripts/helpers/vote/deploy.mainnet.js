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
            "0x42a40321843220e9811A1385D74d9798436f7002", // _vestingAddress
            "0xE420BBb4C2454f305a3335BBdCE069326985fb5b", // _stakingAddress
            "0x03e225D2bd32F5ecE539005B57F9B94A743ADBFB", // _freezerAddress
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
