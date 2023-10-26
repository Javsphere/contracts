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
            chainId: 1133,
            url: "https://testnet-dmc.mydefichain.com:20551",
            accounts: [process.env.OWNER_KEY],
        },
        mainnet: {
            url: "",
            accounts: [process.env.OWNER_KEY],
        },
    },
    etherscan: {
        apiKey: {
            testnet: 'tt'
        },
        customChains: [
            {
                network: "testnet",
                chainId: 1133,
                urls: {
                    apiURL: "https://testnet-dmc.mydefichain.com:8444/api",
                    browserURL: "https://testnet-dmc.mydefichain.com:8444"
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
        enabled: false
    }
};
