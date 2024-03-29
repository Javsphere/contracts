const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JavFreezer");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ethers.parseEther("0.0000005"), //_rewardPerBlock
            30, //_rewardUpdateBlocksInterval
            "0xF977A2D3EA547731f04B19cfDCE00fe9d23dB485", //_vestingAddress
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
    console.log(`JavFreezer contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
