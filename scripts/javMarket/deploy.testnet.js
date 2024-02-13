const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavMarket");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            [
                "0xFF0000000000000000000000000000000000000B",
                "0xFF0000000000000000000000000000000000000c",
                "0xFF0000000000000000000000000000000000000d",
                "0xfF0000000000000000000000000000000000000a",
            ], //_tokensAddresses
            "0x5dB961BF909883e9862e9058c6Fc0737206A8e53", //_botAddress
            "0xFEeC64B26429C85e9B7176C718D53eb84e534669", //_treasuryAddress
            1, //_fee 0.1 %
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
    console.log(`JavMarket contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
