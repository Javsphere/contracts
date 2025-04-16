const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavEscrow");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ["0x83030ec707812Af7e71042fA17153E7fC1822573", "0xc34148F7240B444392974eB6736CB4A93ed6c293"], // availableTokens
            100, // _placeOrderFee - 1%
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavEscrow", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
