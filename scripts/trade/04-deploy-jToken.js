const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("JToken");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            {
                name: "Jav Leverage JAV",
                symbol: "jJAV",
            }, // _meta,
            {
                asset: "0x695D64AdEbD82480f22638E50dA04f6C95df6Ef5",
                owner: "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb", // owner
                manager: "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb", // manager
                admin: "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb", // admin
                lockedDepositNft: "0x53a0f10c549468F6092E25e6C01232B16Fa08876",
                pnlHandler: "0xE299E1e0b1697660AD3aD3b817f565D8Db0d36cb",
                javPriceProvider: {
                    addr: "0x42AAF5456259BA8C0A2b50a00aD6a493459D5826",
                    signature: "0x1de109d2",
                },
            }, // _contractAddresses,
            1209600, //  _MIN_LOCK_DURATION,
            250000000000000000n, //  _maxAccOpenPnlDelta,
            500000000000000000n, //  _maxDailyAccPnlDelta,
            [10000000000000000000n, 20000000000000000000n], // _withdrawLockThresholdsP,
            0, // _lossesBurnP,
            50000000000000000n, //  _maxJavSupplyMintDailyP,
            5000000000000000000n, //  _maxDiscountP,
            150000000000000000000n, // _maxDiscountThresholdP
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

    logDeploy("JToken", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
