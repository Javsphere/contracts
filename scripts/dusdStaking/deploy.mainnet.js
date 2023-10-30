const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DUSDStaking");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x0000000000000000000000000000000000000000", //_tokenAddress
            "0x0000000000000000000000000000000000000000", //_botAddress
            "0x0000000000000000000000000000000000000000", //_serviceSigner
        ],
        {
            initializer: "initialize",
        }
    );
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress()
    console.log(`DUSDStaking contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
