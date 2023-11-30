const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DUSDStaking");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0xFF0000000000000000000000000000000000000B", //_tokenAddress
            "0x2A9f89782B7d3c14a6D5b253c2E059e3572716dc", //_botAddress
        ],

        {
            initializer: "initialize",
            kind: 'uups',
            txOverrides: {
                gasLimit: ethers.parseUnits("0.03", "gwei")
            }
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
