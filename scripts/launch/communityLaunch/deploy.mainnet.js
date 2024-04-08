const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("CommunityLaunch");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ethers.parseEther("15000000"), //_tokensToSale
            ethers.parseEther("0.04"), //_startTokenPrice
            ethers.parseEther("0.05"), //_endTokenPrice
            6, //_sectionsNumber
            [ethers.parseEther("15000000")], //_tokensAmountByType
            {
                tokenAddress: "0x66F3Cf265D2D146A0348F6fC67E3Da0835e0968E",
                stateRelayer: "0xa075dC93D00ac14f4a7416C03cAbec4728586760",
                botAddress: "0x5B339C55eD738c47f5fd6D472b41ec878910AB69",
                dusdAddress: "0xFf0000000000000000000000000000000000000F",
                usdtAddress: "0xFF00000000000000000000000000000000000003",
                pairAddress: "0x36633D610302044FCe7Fd05638C6Ca00E8908788",
                vesting: "0xb32C45dF341930791807c18C4CA2A5E0Ab2D226f",
                freezer: "0x4e15D4225623D07Adb43e9D546E57E1E6097e869",
            },
            {
                cliff: 0, //0 mouth
                duration: 26297430, //10 mouth
                slicePeriodSeconds: 60, //60 seconds
                vestingType: 9, // 0
                lockId: 5, //
            },
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
    console.log(`CommunityLaunch contract deployed to: ${contractAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
