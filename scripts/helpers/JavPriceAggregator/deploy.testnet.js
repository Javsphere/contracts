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
            1, //_priceUpdateFee
            ["0x7c9c28a342bf4CB8d34C33E93C3E4b71ADA2b9a2"], //_allowedAddresses_
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
