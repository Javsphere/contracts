const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DutchAuctionFactory");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x0000000000000000000000000000000000000000", //_tokenAddress
            2,                                            //_minimumSignatures
            [                                             //_signers
                "0x0000000000000000000000000000000000000000",
                "0x0000000000000000000000000000000000000000",
                "0x0000000000000000000000000000000000000000"
            ]
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
    console.log(`DutchAuctionFactory contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
