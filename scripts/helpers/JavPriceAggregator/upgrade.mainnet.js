const { ethers, upgrades } = require("hardhat");
const PROXY = "0xc0bAF6200639C52821245BEcc757480Eb03A4e3e";

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory(
        "contracts/helpers/JavPriceAggregator.sol:JavPriceAggregator",
    );

    const impl = await upgrades.upgradeProxy(PROXY, Contract, {
        kind: "uups",
        redeployImplementation: "always",
    });
    await impl.waitForDeployment();

    console.log(`Upgrade Finished..`);
    console.log(`Starting Verification..`);

    let newImplementationAddress = await upgrades.erc1967.getImplementationAddress(PROXY);

    try {
        await run("verify:verify", { address: PROXY });
    } catch (error) {
        if (!error.message.includes("Reason: Already Verified")) {
            console.error(error);
            console.log(`\nVerification of  new implementation failed!`);
            console.log(`But contract was deployed at Address: ${newImplementationAddress}`);
            process.exit(1);
        }
    }

    console.log(`New implementation Address: ${newImplementationAddress}`);
    console.log(`JavPriceAggregator contract upgraded`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
