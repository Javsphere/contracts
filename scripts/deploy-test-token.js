const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("TestUSDT");
    const contract = await upgrades.deployProxy(Contract, [], {
        initializer: "initialize",
        kind: "uups",
    });
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress();
    console.log(`TestUSDT contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
