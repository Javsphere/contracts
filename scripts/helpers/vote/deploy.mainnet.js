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
            "0x7246ad1ac72715c5fd6c1FD7460A63afB8289104", // _vestingAddress
            "0xF923f0828c56b27C8f57bc698c99543f63091E9A", // _stakingAddress
            "0x4e15D4225623D07Adb43e9D546E57E1E6097e869", // _freezerAddress
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
