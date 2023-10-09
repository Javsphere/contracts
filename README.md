# Javlis smart contracts

## Getting started

### Install dependencies

```shell
yarn install
```

### Deploy contract

```shell
npx hardhat run --network <network> <path_to_script>
```

### Verify contract

```shell
npx hardhat verify <contract_address> --network <network>
```

### Hardhat tools

```shell
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
npx hardhat coverage
npx hardhat flatten
```

### Deploy

1. ProxyAdmin
2. JavToken


.openzeppelin/unknown-1133.json
{
  "manifestVersion": "3.2",
  "admin": {
    "address": "admin-address",
    "txHash": "admin-tx"
  },
  "proxies": [],
  "impls": {}
}
