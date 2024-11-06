const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("Vote");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb", // _adminAddress
            "0x42a40321843220e9811A1385D74d9798436f7002", // _vestingAddress
            "0x67664a9D58357Bb92Ea6187bD06f33748e74B8d6", // _stakingAddress
            "0xB86695ADF328AA1CDfE5b1ac0229554f0194C7a8", // _freezerAddress
            25, // _stakingFactor
            2000, // _vestingFactor
            [0, 1, 2, 3, 4, 5, 6], // _freezerIdsFactor
            [100, 350, 800, 1750, 3900, 700, 1500], // _freezerFactors
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("Vote", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
