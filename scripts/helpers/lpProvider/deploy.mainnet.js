const { ethers, upgrades } = require("hardhat");
const {logDeploy} = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("LPProvider");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x420DD381b31aEf6683db6B902084cB0FFECe40Da", //_poolFactory
            "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43", //_routerAddress
            "0x5B339C55eD738c47f5fd6D472b41ec878910AB69", //_botAddress
        ],
        {
            initializer: "initialize",
            kind: "uups",

        },
    );
    await contract.waitForDeployment();

    logDeploy("LPProvider", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
