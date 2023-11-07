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
3. Remaining contracts


### Testnet deployment
1. Deploy proxyAdmin and verify it
2. Create file and pass info about proxyAdmin
`.openzeppelin/unknown-1131.json`
```json
{
  "manifestVersion": "3.2",
  "admin": {
    "address": "admin-address",
    "txHash": "admin-tx"
  },
  "proxies": [],
  "impls": {}
}
```
3. Deploy others contract
4. ...
