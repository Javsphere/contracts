const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const owners = [
        "0x8D50eE492c9c3a8174aA39c377839944dc546378",
        "0xc6F5fA4a1039a041Fc41f634FC07641f87C8Cf2b",
        "0x61878A8365C63eFe8db686e5c1101778aCcee815",
    ];
    const minRequiredCount = 2;

    const Contract = await ethers.getContractFactory("MultiSigWallet");
    const contract = await Contract.deploy(owners, minRequiredCount);
    console.log(`MultiSigWallet contract deployed to: ${contract.target}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
