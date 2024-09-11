require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-solhint");
require("hardhat-contract-sizer");
require("solidity-docgen");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.24",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: "0.8.20",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
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
    },
    etherscan: {
        apiKey: {
            testnet: "abc",
            mainnet: "abc",
            sepolia_base: "abc",
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
        ],
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: true,
        disambiguatePaths: false,
    },
    gasReporter: {
        enabled: true,
    },
};
