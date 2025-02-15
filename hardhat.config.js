require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-solhint");
require("hardhat-contract-sizer");
require("solidity-docgen");

// Remove deprecated folder from compile task
const { subtask } = require("hardhat/config");
const { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } = require("hardhat/builtin-tasks/task-names");

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
    const paths = await runSuper();

    return paths.filter((p) => !p.includes("deprecated"));
});

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.26",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                    viaIR: true,
                },
            },
            {
                version: "0.8.24",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
                viaIR: true,
            },
        ],
    },
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            chainId: 31337,
            blockGasLimit: 1000000000,
        },
        testnet: {
            chainId: 1131,
            url: "https://dmc.mydefichain.com/testnet",
            accounts: [process.env.OWNER_KEY],
        },
        mainnet: {
            chainId: 1130,
            url: "https://dmc.mydefichain.com/mainnet",
            accounts: [process.env.OWNER_KEY],
        },
        sepolia_base: {
            chainId: 84532,
            url: "https://sepolia.base.org",
            accounts: [process.env.OWNER_KEY],
        },
        base: {
            chainId: 8453,
            url: "https://mainnet.base.org",
            accounts: [process.env.OWNER_KEY],
        },
    },
    etherscan: {
        apiKey: {
            testnet: "abc",
            mainnet: "abc",
            sepolia_base: process.env.BASE_API_KEY,
            base: process.env.BASE_API_KEY,
        },
        customChains: [
            {
                network: "testnet",
                chainId: 1131,
                urls: {
                    apiURL: "https://blockscout.testnet.ocean.jellyfishsdk.com/api",
                    // apiURL: "https://testnet-dmc.mydefichain.com/api",
                    browserURL: "https://blockscout.testnet.ocean.jellyfishsdk.com",
                    // browserURL: "https://testnet-dmc.mydefichain.com",
                },
            },
            {
                network: "mainnet",
                chainId: 1130,
                urls: {
                    apiURL: "https://blockscout.mainnet.ocean.jellyfishsdk.com/api",
                    // apiURL: "https://mainnet-dmc.mydefichain.com/api",
                    browserURL: "https://blockscout.mainnet.ocean.jellyfishsdk.com",
                    // browserURL: "https://mainnet-dmc.mydefichain.com",
                },
            },
            {
                network: "sepolia_base",
                chainId: 84532,
                urls: {
                    // apiURL: "https://base-sepolia.blockscout.com/api",
                    apiURL: "https://api-sepolia.basescan.org/api",
                    // browserURL: "https://base-sepolia.blockscout.com/",
                    browserURL: "https://sepolia.basescan.org/",
                },
            },
            {
                network: "base",
                chainId: 8453,
                urls: {
                    apiURL: "https://api.basescan.org/api",
                    // apiURL: "https://base.blockscout.com/api",
                    browserURL: "https://basescan.org/",
                    // browserURL: "https://base.blockscout.com/",
                },
            },
        ],
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: false,
        disambiguatePaths: false,
    },
    gasReporter: {
        enabled: false,
    },
};
