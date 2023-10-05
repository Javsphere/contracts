const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavlisToken");
    const contract = await upgrades.deployProxy(
        Contract,
        [
        ],
        {
            initializer: "initialize",
        }
    );
    await contract.deployed();
    console.log(`JavlisToken contract deployed to: ${contract.address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
