const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavFreezer");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ethers.parseEther("140"), //_rewardPerBlock
            0, //_rewardUpdateBlocksInterval
            "0x05Ab310524968Fda05431F7FA8858351FD190eba", //_vestingAddress
            10, //_infinityPassPercent
            "0xdcD2ECce51a80Ccf23e8a767A0BFe3546CDAE7a6", //_infinityPass
            "0x0000000000000000000000000000000000000000", //_migratorAddress
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
