const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("CommunityLaunchETH");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xc0bAF6200639C52821245BEcc757480Eb03A4e3e", //_usdtAddress bsc
            ethers.parseEther("10000"), //_availableTokens
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
