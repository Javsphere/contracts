const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavToken");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ethers.parseEther("2000000000"), //_cap
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    const contractAddress = await contract.getAddress();
    console.log(`JavToken contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
