const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavBorrowingProvider");
    const baseArgs = [
        "0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a", //_priceAggregator,
        "0x0000000000000000000000000000000000000000", // _swapRouter,
        "0x8Fdc017195Ba2D22186E4b442497F5B19f870a64", // _llpToken,
        "0xDEFf0d5bAAb58985aC3b2E61B82108Cc1900aF8a", // _pnlHandler,
        5, // _buyFee,
        5, // _sellFee,
        [
            {
                asset: "0x4200000000000000000000000000000000000006",  //weth
                priceFeed: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
                targetWeightage: 33,
                isActive: true,
            },
            {
                asset: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", //cbTBC
                priceFeed: "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
                targetWeightage: 33,
                isActive: true,
            },
            {
                asset: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", //usdc
                priceFeed: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
                targetWeightage: 33,
                isActive: true,
            },
        ], // _tokens
    ];

    const sepolia_baseArgs = [
        "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729", //_priceAggregator,
        "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4", // _swapRouter,
        "0xc9a58Cef2d9e9D2A5DFB76F52E8AA0fDb548958E", // _llpToken,
        "0xB8057B1605e25c1D8CDE6F9f875d7bcFe4A0fE33", // _pnlHandler,
        5, // _buyFee,
        5, // _sellFee,
        [
            {
                asset: "0xCfC5DD6AF77b5BccB6adceD68716f98c69463b03", //weth
                priceFeed: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
                targetWeightage: 25,
                isActive: true,
            },
            {
                asset: "0xB86fBB7C463e189fE50529491E8bDc05714f6634", //tWBTC:
                priceFeed: "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
                targetWeightage: 25,
                isActive: true,
            },
            {
                asset: "0xc34148F7240B444392974eB6736CB4A93ed6c293", //tUSDT:
                priceFeed: "0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b",
                targetWeightage: 25,
                isActive: true,
            },
            {
                asset: "0x66F3Cf265D2D146A0348F6fC67E3Da0835e0968E", //tUSDC:
                priceFeed: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
                targetWeightage: 25,
                isActive: true,
            },
        ], // _tokens
    ];
    const contract = await upgrades.deployProxy(Contract, baseArgs, {
        initializer: "initialize",
        kind: "uups",
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
