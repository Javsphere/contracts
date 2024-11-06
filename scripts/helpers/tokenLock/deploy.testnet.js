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
            "0x695D64AdEbD82480f22638E50dA04f6C95df6Ef5", // _tokenAddress
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
