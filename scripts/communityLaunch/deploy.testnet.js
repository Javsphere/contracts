const {ethers, upgrades} = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("CommunityLaunch");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x31C4Afcef7277801f460A4d04B5966286a28A295", //_tokenAddress
            0,                                            //_startTokenPrice
            0,                                            //_incPricePerBlock
            2,                                            //_minimumSignatures
            [                                             //_signers
                "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb",
                "0x229201eeE335Bcf2aC2F3553dcAF613A70331157",
                "0x01C4679164306967BbEd08926B50bcDE240c9f0b"
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
    console.log(`CommunityLaunch contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
