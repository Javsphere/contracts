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
            ["0xed778ED7aC2AA1C4AD4Ba9F2c0818B44316E8f6a"], //_allowedSigners_
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
