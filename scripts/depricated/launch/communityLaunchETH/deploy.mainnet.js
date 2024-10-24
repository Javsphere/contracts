const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("CommunityLaunchETH");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xdAC17F958D2ee523a2206206994597C13D831ec7", //_usdtAddress
            ethers.parseEther("1000"), //_availableTokens
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress();
    console.log(`CommunityLaunchETH contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
