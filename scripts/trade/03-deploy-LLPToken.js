const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("LLPToken");
    const contract = await upgrades.deployProxy(Contract, [], {
        initializer: "initialize",
        kind: "uups",
    });
    await contract.waitForDeployment();

    logDeploy("LLPToken", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
