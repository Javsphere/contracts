const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("BaseMigrator");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9", // _tokenAddress
            "0x42a40321843220e9811A1385D74d9798436f7002", // _vestingAddress
            "0x672BC764615FF9126541f7eb999fc089639d53fe", // _vestingFreezerAddress
            "0xE420BBb4C2454f305a3335BBdCE069326985fb5b", // _stakingAddress
            "0x03e225D2bd32F5ecE539005B57F9B94A743ADBFB", // _freezerAddress
            "0xBC2bB8c25162203528A4b5f50890736D8B897E7a", // _infinityPass
            "0x0000000000000000000000000000000000000000", // _signerAddress
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("BaseMigrator", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
