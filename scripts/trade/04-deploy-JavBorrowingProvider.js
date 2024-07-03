const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavBorrowingProvider");
    const mainnetArgs = [
        "0x0000000000000000000000000000000000000000", //_priceAggregator,
        "0x0000000000000000000000000000000000000000", // _swapRouter,
        "0x0000000000000000000000000000000000000000", // _jlpToken,
        "0x0000000000000000000000000000000000000000", // _pnlHandler,
        1, // _buyFee,
        2, // _sellFee,
        [
            {
                asset: "0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0",
                priceFeed: "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6",
                targetWeightage: 50,
                isActive: true,
            },
            {
                asset: "0x9A676e781A523b5d0C0e43731313A708CB607508",
                priceFeed: "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6",
                targetWeightage: 50,
                isActive: true,
            },
        ], // _tokens
    ];
    const testnetArgs = [
        "0x900eD05e6c662D1A410d75A9ec30840647B4F1B0", //_priceAggregator,
        "0x0000000000000000000000000000000000000000", // _swapRouter,
        "0xf87f1eA1Ddb9845ef19Dc102495229a6f87C26bd", // _jlpToken,
        "0x9f907D14db8C20BE152e0296EC4a8f32cce4A632", // _pnlHandler,
        5, // _buyFee,
        5, // _sellFee,
        [
            {
                asset: "0x695D64AdEbD82480f22638E50dA04f6C95df6Ef5", //jav
                priceFeed: "0x2c14b4d35d0e7061b86be6dd7d168ca1f919c069f54493ed09a91adabea60ce6",
                targetWeightage: 50,
                isActive: true,
            },
            {
                asset: "0xFF0000000000000000000000000000000000000B", //dusd
                priceFeed: "0xb3b9faf5d52f4cc87ec09fd94cb22c9dc62a8c1759b2a045faae791f8771a723",
                targetWeightage: 50,
                isActive: true,
            },
        ], // _tokens
    ];
    const contract = await upgrades.deployProxy(Contract, testnetArgs, {
        initializer: "initialize",
        kind: "uups",
        txOverrides: {
            gasLimit: ethers.parseUnits("0.03", "gwei"),
        },
    });
    await contract.waitForDeployment();

    logDeploy("JavBorrowingProvider", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
