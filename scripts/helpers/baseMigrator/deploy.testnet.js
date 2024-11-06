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
            "0x83030ec707812Af7e71042fA17153E7fC1822573", // _tokenAddress
            "0x85FCe36f585B1E78058B86B6FC57E026050184CF", // _vestingAddress
            "0x05Ab310524968Fda05431F7FA8858351FD190eba", // _vestingFreezerAddress
            "0x2c25e215fCb76Ba18F85a6E31C831286b09055B4", // _stakingAddress
            "0xe7E65d1c76293CF2367b6545A763a84d347E3658", // _freezerAddress
            "0xdcD2ECce51a80Ccf23e8a767A0BFe3546CDAE7a6", // _infinityPass
            "0x51cdb3fe30E7fbEd9Df51EE7E0BF636f69137299", // _signerAddress
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
