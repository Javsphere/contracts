const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("TokenLock");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x66F3Cf265D2D146A0348F6fC67E3Da0835e0968E", // _tokenAddress
            "0x0000000000000000000000000000000000000000", // _migrator
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("TokenLock", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
