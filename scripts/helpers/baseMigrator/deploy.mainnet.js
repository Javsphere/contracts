const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("BaseMigrator");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x0000000000000000000000000000000000000000", // _tokenAddress
            "0x0000000000000000000000000000000000000000", // _vestingAddress
            "0x0000000000000000000000000000000000000000", // _vestingFreezerAddress
            "0x0000000000000000000000000000000000000000", // _stakingAddress
            "0x0000000000000000000000000000000000000000", // _freezerAddress
            "0x0000000000000000000000000000000000000000", // _infinityPass
            "0x0000000000000000000000000000000000000000", // _signerAddress
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("BaseMigrator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
