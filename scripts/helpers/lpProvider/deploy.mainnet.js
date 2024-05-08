const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("LPProvider");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "0x274567C3B27F3981C4Ae7C951ECDe1C2aE70e6d0", //_nonfungiblePositionManager
            "0x3E8C92491fc73390166BA00725B8F5BD734B8fba", //_routerAddressV2
            "0x2A9c4EdE9994911359af815367187947eD1dDf02", //_swapRouter
            "0x5B339C55eD738c47f5fd6D472b41ec878910AB69", //_botAddress
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
    console.log(`LPProvider contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
