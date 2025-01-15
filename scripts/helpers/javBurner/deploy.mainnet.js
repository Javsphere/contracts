const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavBurner");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9", // _javAddress
            "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43", // _swapRouterAddress
            ["0x51cdb3fe30E7fbEd9Df51EE7E0BF636f69137299"], // _allowedAddresses_

        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavBurner", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
