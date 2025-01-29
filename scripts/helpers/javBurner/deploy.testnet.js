const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavBurner");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x83030ec707812Af7e71042fA17153E7fC1822573", // _javAddress
            "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43", // _swapRouterAddress
            ["0x0CB952f45b5bDE5aA0e93862707bf34F2EE1E452", "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb"], // _allowedAddresses_

        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    logDeploy("JavBurner", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
