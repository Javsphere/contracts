const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DMCMigrator");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x66F3Cf265D2D146A0348F6fC67E3Da0835e0968E", // _tokenAddress
            "0x56212008575D37e7B29e1CfAAa5f325d1daE57cE", // _tokenLockAddress
            "0x7246ad1ac72715c5fd6c1FD7460A63afB8289104", // _vestingAddress
            "0xb32C45dF341930791807c18C4CA2A5E0Ab2D226f", // _vestingFreezerAddress
            "0xF923f0828c56b27C8f57bc698c99543f63091E9A", // _stakingAddress
            "0x4e15D4225623D07Adb43e9D546E57E1E6097e869", // _freezerAddress
            "0xd66e71BF4334308ecb550377590078434685B6bE", // _infinityPass
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("DMCMigrator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
