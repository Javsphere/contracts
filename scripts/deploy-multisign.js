const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("./utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const owners = [
        "0x0c787ca33Ae184C6c7b943593c7C437e3b8A2498",
        "0xd040d43981E9520425168A414c98A02AAD3DcaC2",
        "0x2adB61b0EE29cA83E83a5157b99DB773C716e629",
    ];
    const minRequiredCount = 2;

    const Contract = await ethers.getContractFactory("MultiSigWallet");
    const contract = await Contract.deploy(owners, minRequiredCount);
    logDeploy("MultiSigWallet", contract.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
