const { ethers, upgrades } = require("hardhat");
const {logDeploy} = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("RewardsDistributor");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9", // _javAddress,
            "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43", // _swapRouter,
            "0xE420BBb4C2454f305a3335BBdCE069326985fb5b", // _stakingAddress,
            "0x03e225D2bd32F5ecE539005B57F9B94A743ADBFB", // _freezerAddress,
            50, // _burnPercent,
            70, // _freezerPercent,
            [
                "0xeDdF88551824918fdC98907732f92c62dBb827AA",
                "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb",
            ], // _allowedAddresses_
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("RewardsDistributor", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
