const { ethers, upgrades } = require("hardhat");
const {logDeploy} = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("TokenVesting");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xEdC68c4c54228D273ed50Fc450E253F685a2c6b9", //_token
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("TokenVesting", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
