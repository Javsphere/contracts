const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JTOKENLockedDepositNft");
    const contract = await Contract.deploy("jJAV Locked Deposit", "jJAVLD");

    await contract.waitForDeployment();

    logDeploy("JTOKENLockedDepositNft", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
