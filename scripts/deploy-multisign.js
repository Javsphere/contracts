const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const owners = [
        "0xFEeC64B26429C85e9B7176C718D53eb84e534669",
        "0x0E8627A1E68dE2F6e657e7A1efaf4AFc0dB338B3",
        "0x267A2a67a1E0c8be282D00C238b3F4bF17164f56",
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
