const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("./utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);

    const tokenFactory = await ethers.getContractFactory("TestToken");
    // const token1 = await upgrades.deployProxy(tokenFactory, ["Leverage WBTC", "xWBTC"], {
    //     initializer: "initialize",
    //     kind: "uups",
    // });
    // await token1.waitForDeployment();
    //
    // logDeploy("xWBTC", await token1.getAddress());
    //
    // const token2 = await upgrades.deployProxy(tokenFactory, ["Leverage WETH", "xWETH"], {
    //     initializer: "initialize",
    //     kind: "uups",
    // });
    // await token2.waitForDeployment();
    //
    // logDeploy("xWETH", await token2.getAddress());

    const token3 = await upgrades.deployProxy(tokenFactory, ["decimals cbBTC", "dUSDC"], {
        initializer: "initialize",
        kind: "uups",
    });
    await token3.waitForDeployment();

    logDeploy("xUSDC", await token3.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
