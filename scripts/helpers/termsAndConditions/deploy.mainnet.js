const { ethers, upgrades } = require("hardhat");
const { logDeploy } = require("../../utils");

async function main() {
    const [owner] = await ethers.getSigners();
    // We get the contract to deploy
    console.log(`Deploying from ${owner.address}`);
    const Contract = await ethers.getContractFactory("TermsAndConditionsAgreement");
    const contract = await upgrades.deployProxy(
        Contract,
        [
            "test", //_agreementsUrl
        ],
        {
            initializer: "initialize",
            kind: "uups",
        },
    );

    await contract.waitForDeployment();

    logDeploy("TermsAndConditionsAgreement", await contract.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
