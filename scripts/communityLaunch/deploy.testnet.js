const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("CommunityLaunch");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x0B2Ae4E47bF3Eb3BD66AD7e38ff152076Ef24323", //_tokenAddress
            0, //_javPrice
        ],
        {
            initializer: "initialize",
        }
    );
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress()
    console.log(`CommunityLaunch contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
