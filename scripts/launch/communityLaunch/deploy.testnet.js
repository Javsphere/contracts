const { ethers, upgrades } = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("CommunityLaunch");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            ethers.parseEther("1000"), //_tokensToSale
            ethers.parseEther("1"), //_startTokenPrice
            ethers.parseEther("2"), //_endTokenPrice
            6, //_sectionsNumber
            [ethers.parseEther("500")], //_tokensAmountByType
            {
                tokenAddress: "0x695D64AdEbD82480f22638E50dA04f6C95df6Ef5",
                stateRelayer: "0xA6A853DDbfB6C85d3584E33313628555BA85753B",
                botAddress: "0x0000000000000000000000000000000000000000",
                dusdAddress: "0xFF0000000000000000000000000000000000000B",
                usdtAddress: "0xD19A9DDD25e35bb264f59771EfdB59997613958e",
                pairAddress: "0xfF861090A65D2c062f22Ab1f606e2D39bed5C8EC",
                vesting: "0x0000000000000000000000000000000000000000",
                freezer: "0x0000000000000000000000000000000000000000",
            },
            {
                cliff: 300, //5 min
                duration: 7200, //2 hour
                slicePeriodSeconds: 60, //60s
                vestingType: 0, //
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
