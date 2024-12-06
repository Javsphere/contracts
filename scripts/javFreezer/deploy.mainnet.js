const { ethers, upgrades } = require("hardhat");
const {logDeploy} = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("contracts/JavFreezer.sol:JavFreezer");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x672BC764615FF9126541f7eb999fc089639d53fe", //_vestingAddress
            10, //_infinityPassPercent
            "0xBC2bB8c25162203528A4b5f50890736D8B897E7a", //_infinityPass
            "0x0000000000000000000000000000000000000000", //_migratorAddress
            "0x0000000000000000000000000000000000000000", //_termsAndConditionsAddress
        ],
        {
            initializer: "initialize",
            kind: "uups",

        },
    );
    await contract.waitForDeployment();

    logDeploy("JavFreezer", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
