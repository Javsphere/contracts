const {ethers, upgrades} = require("hardhat");

async function main() {
    const address = await upgrades.erc1967.getAdminAddress("0x0000000000000000000000000000000000000000");
    console.log(`ProxyAdmin is at: ${address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
