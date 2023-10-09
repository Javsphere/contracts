const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();

    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const ProxyAdminFactory = await ethers.getContractFactory('contracts/proxy/ProxyAdmin.sol:ProxyAdmin');
    const proxyAdmin = await ProxyAdminFactory.deploy();
    await proxyAdmin.waitForDeployment();

    const proxyAdminAddress = await proxyAdmin.getAddress()

    console.log('ProxyAdmin deployed to:', proxyAdminAddress);
    console.log('Start verification');

    await run("verify:verify", {
        address: proxyAdminAddress,
        contract: "contracts/proxy/ProxyAdmin.sol:ProxyAdmin",
        constructorArguments: []
    });

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
