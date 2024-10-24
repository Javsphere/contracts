const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DMCMigrator");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x695D64AdEbD82480f22638E50dA04f6C95df6Ef5", // _tokenAddress
            "0xdfc8c41816Cd6CCa9739f946e73b4eeB17195836", // _tokenLockAddress
            "0x42a40321843220e9811A1385D74d9798436f7002", // _vestingAddress
            "0xF977A2D3EA547731f04B19cfDCE00fe9d23dB485", // _vestingFreezerAddress
            "0x67664a9D58357Bb92Ea6187bD06f33748e74B8d6", // _stakingAddress
            "0xB86695ADF328AA1CDfE5b1ac0229554f0194C7a8", // _freezerAddress
            "0x60b6860F25A7503Bcb5A2ce0940E61D5e503A056", // _infinityPass
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("DMCMigrator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
