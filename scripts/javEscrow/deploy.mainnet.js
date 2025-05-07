const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavEscrow");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ["0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9", "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"], // availableTokens
            100, // _placeOrderFee - 1%
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavEscrow", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
