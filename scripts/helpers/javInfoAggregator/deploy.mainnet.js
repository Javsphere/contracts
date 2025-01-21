const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavInfoAggregator");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9", // _javAddress
            "0xAEC880bAdc135c6a72Be280A87A2fea513B51C8F", // _javPool
            "0x42a40321843220e9811A1385D74d9798436f7002", // _vestingAddress
            "0xE420BBb4C2454f305a3335BBdCE069326985fb5b", // _stakingAddress
            "0x03e225D2bd32F5ecE539005B57F9B94A743ADBFB", // _freezerAddress
            "0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a", // _priceAggregator

        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavInfoAggregator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
