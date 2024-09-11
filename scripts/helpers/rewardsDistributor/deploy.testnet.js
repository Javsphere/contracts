const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("RewardsDistributor");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x695D64AdEbD82480f22638E50dA04f6C95df6Ef5", // _javAddress,
            "0x0000000000000000000000000000000000000000", // _swapRouter,
            "0x67664a9D58357Bb92Ea6187bD06f33748e74B8d6", // _stakingAddress,
            "0xB86695ADF328AA1CDfE5b1ac0229554f0194C7a8", // _freezerAddress,
            50, // _burnPercent,
            70, // _freezerPercent,
            ["0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb"], // _allowedAddresses_
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
