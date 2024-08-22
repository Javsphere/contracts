const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory(
        "contracts/helpers/JavPriceAggregator.sol:JavPriceAggregator",
    );
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ["0x8D50eE492c9c3a8174aA39c377839944dc546378"], //_allowedAddresses_
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavPriceAggregator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
