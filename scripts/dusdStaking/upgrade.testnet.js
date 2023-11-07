const { ethers, upgrades } = require("hardhat");
const PROXY = "0x91Ce55CaFD0Fcd12445A82eD12e8aa6975d6e8a4";

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("DUSDStaking");

    // const deployment = await upgrades.forceImport(PROXY, Contract);
    // console.log("Proxy imported from:", deployment.address);

    const impl = await upgrades.upgradeProxy(
      PROXY,
      Contract
    );
    await impl.waitForDeployment();

    console.log(`Upgrade Finished..`)
    console.log(`Starting Verification..`);

    let newImplementationAddress = await upgrades.erc1967.getImplementationAddress(PROXY);
    
    try{
        await run("verify:verify", { address: newImplementationAddress});
    } catch(error) {
        if(!error.message.includes("Reason: Already Verified")) {
            console.error(error);
            console.log(`\nVerification of  new implementation failed!`)
            console.log(`But contract was deployed at Address: ${newImplementationAddress}`)
            process.exit(1);
        }
    };

    console.log(`New implementation Address: ${newImplementationAddress}`);
    console.log(`DUSDStaking contract upgraded`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
