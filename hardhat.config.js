require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-chai-matchers")
require("@nomiclabs/hardhat-solhint");
require("hardhat-contract-sizer");
require('solidity-docgen');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
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
            blockGasLimit: 1000000000
        },
        testnet: {
            chainId: 1131,
            url: "https://dmc.mydefichain.com/testnet",
            accounts: [process.env.OWNER_KEY],
        },
        mainnet: {
            url: "",
            accounts: [process.env.OWNER_KEY],
        },
    },
    etherscan: {
        apiKey: {
            testnet: "abc"
        },
        customChains: [
            {
                network: "testnet",
                chainId: 1131,
                urls: {
                    apiURL: "https://testnet3-dmc.mydefichain.com:8445/api",
                    browserURL: "https://testnet3-dmc.mydefichain.com:8445"
                }
            }
        ]
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: true,
        disambiguatePaths: false,
    },
    gasReporter: {
        enabled: true
    }
};
