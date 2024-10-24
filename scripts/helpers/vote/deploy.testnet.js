const {ethers, upgrades} = require("hardhat");
const {logDeploy} = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("Vote");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x0000000000000000000000000000000000000000", // _adminAddress
            "0x0000000000000000000000000000000000000000", // _vestingAddress
            "0x0000000000000000000000000000000000000000", // _stakingAddress
            "0x0000000000000000000000000000000000000000", // _freezerAddress
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
