require("dotenv").config();
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-solhint");
require('solidity-docgen');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            chainId: 31337,
            blockGasLimit: 1000000000
        },
        testnet: {
            url: "",
            accounts: [process.env.OWNER_KEY],
        },
        mainnet: {
            url: "",
            accounts: [process.env.OWNER_KEY],
        },
    },
};
