# Azuro totalizator

## Documentation

- [Developer](./docs/index.html)  
- [Oracle](./docs/oracle/index.html)  
- [Bettor](./docs/bettor/index.html)
## Usage
### Prerequisites
1. Install hardhat locally in the project folder:
   ```
   npm install --save-dev hardhat
   ```
### Compile

```
npm run compile
```

### Test

```
npm run test
```

### Run local node

```
npm run node
```

### Deploy contract
1. Fill up environment with networks keys you are going to use:
   - **ALCHEMY_API_KEY_RINKEBY** (for node connection)
   - **ALCHEMY_API_KEY_KOVAN** (for node connection)
   - **KOVAN_PRIVATE_KEY**
   - **RINKEBY_PRIVATE_KEY**
   - **MAINNET_PRIVATE_KEY**
   - **BSC_PRIVATE_KEY**
   - **ETHERSCAN_API_KEY** (for contract verification)
2. Run command:
   ```
   npm run deploy %network%
   ```
   where **%network%** is name of network you would deploy your contract to.
### Upgrade contract
1. Fill up **CONTRACT_ADDRESS** environment key with address of deployed TotoBetting proxy.  
2. Run command:
   ```
   npm run upgrade %network%
   ```
   where **%network%** is name of network where you would like to upgrade your contract.

