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
            "0x0000000000000000000000000000000000000000", //_multiSignWallet
            0,                                            //_startTokenPrice
            0,                                            //_incPricePerBlock

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
