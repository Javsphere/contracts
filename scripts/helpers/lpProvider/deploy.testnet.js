const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("LPProvider");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            nonfungiblePositionManager.target, //_nonfungiblePositionManager
            "0x3E8C92491fc73390166BA00725B8F5BD734B8fba", //_routerAddressV2
            uniswapV3Router.target, //_swapRouter
            bot.address, //_botAddress
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
