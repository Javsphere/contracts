const { ethers, upgrades } = require("hardhat");

async function main() {
    const address = await upgrades.erc1967.getAdminAddress(
        "0x525A510238313a5AE9Fdf9212Ff2807AE529290a",
    );
    console.log(`ProxyAdmin is at: ${address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
