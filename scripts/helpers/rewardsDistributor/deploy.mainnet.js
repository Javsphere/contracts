const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("RewardsDistributor");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x66F3Cf265D2D146A0348F6fC67E3Da0835e0968E", // _javAddress,
            "0x2A9c4EdE9994911359af815367187947eD1dDf02", // _swapRouter,
            "0xF923f0828c56b27C8f57bc698c99543f63091E9A", // _stakingAddress,
            "0x4e15D4225623D07Adb43e9D546E57E1E6097e869", // _freezerAddress,
            50, // _burnPercent,
            70, // _freezerPercent,
            [
                "0x9065F4D6fB7B940D64941542c728f3883dE04FdC",
                "0x51cdb3fe30E7fbEd9Df51EE7E0BF636f69137299",
            ], // _allowedAddresses_
        ],
        {
            initializer: "initialize",
            kind: "uups",
            txOverrides: {
                gasLimit: ethers.parseUnits("0.03", "gwei"),
            },
        },
    );
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress();
    console.log(`RewardsDistributor contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
