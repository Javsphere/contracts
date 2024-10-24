const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DUSDStaking");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xFf0000000000000000000000000000000000000F", //_tokenAddress
            "0xe0cfb44cD4a1137fE7B1c6B495D1c6e19140ECe5", //_botAddress
        ],
        {
            initializer: "initialize",
            kind: "uups",
            txOverrides: {
                gasLimit: ethers.parseUnits("0.03", "gwei"),
            },
        },
    );
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress();
    console.log(`DUSDStaking contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
