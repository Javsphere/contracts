const { ethers, upgrades } = require("hardhat");
const {logDeploy} = require("./utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    // const Contract = await ethers.getContractFactory("TestUSDT");
    // const contract = await upgrades.deployProxy(Contract, [], {
    //     initializer: "initialize",
    //     kind: "uups",
    // });
    // await contract.waitForDeployment();
    //
    // const contractAddress = await contract.getAddress();
    // console.log(`TestUSDT contract deployed to: ${contractAddress}`);


    const tokenFactory = await ethers.getContractFactory("TestToken");
    const token1 = await upgrades.deployProxy(tokenFactory, ["Test WBTC", "wBTC"], {
            initializer: "initialize",
            kind: "uups",
        });
    await token1.waitForDeployment();

    logDeploy("tWBTC", await token1.getAddress());

    const token2 = await upgrades.deployProxy(tokenFactory, ["Test USDT", "tUSDT"], {
        initializer: "initialize",
        kind: "uups",
    });
    await token2.waitForDeployment();

    logDeploy("tUSDT", await token2.getAddress());

    const token3 = await upgrades.deployProxy(tokenFactory, ["Test USDC", "tUSDC"], {
        initializer: "initialize",
        kind: "uups",
    });
    await token3.waitForDeployment();

    logDeploy("tUSDC", await token3.getAddress());

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
