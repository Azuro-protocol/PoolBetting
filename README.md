# Azuro totalizator

## Documentation

- [Developer](https://htmlpreview.github.io/?https://github.com/Azuro-protocol/PoolBetting/blob/main/docs/index.html#/)  

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
   - **RINKEBY_PRIVATE_KEY**
   - **ETHERSCAN_API_KEY** (for contract verification)
2. Run command:
   ```
   npm run deploy %network%
   ```
   where **%network%** is name of network you would deploy your contract to.
### Upgrade contract
1. Fill up **CONTRACT_ADDRESS** environment key with address of deployed PoolBetting proxy.  
2. Run command:
   ```
   npm run upgrade %network%
   ```
   where **%network%** is name of network where you would like to upgrade your contract.


## Gnosis main network
### Contracts
```
PoolBetting  0x7e16682b9f0C930463FCd82c3Cf4b96dB899bDFC
Impl         0x3CFF24f3d7B54cac716889c77B538Fb4005D3de9
```

## Rinkeby test network
### Contracts
```
PoolBetting  0x5e74127D022A8471b9090B227A5aac534231BaA4
Impl         0xbCd45D027bDC3Af1d9916aebCd0a2fE506015b20
USDT         0xfF20e2e5768C666e873EB355ee48Ad16cAC317ee
```
### Test accounts
```
Wallet1      0x13c9ca8cc4b1504368a541e21faac4da2ae7f0cc
PrivKey1     317fae20a06d46b6d9e90b2541064ba568acc71e4938ad214e691f5e6edfddc1

Wallet2      0x67256a33e9be491d15ae46b8b5ad6c2f04678dd6
PrivKey2     99aad12967457becf8f0e67356e02d0c05210399e83c7721a7547d77f92e5fc4

Wallet3      0xa86a550c4c2b586966b6da923c4068d0aeaef5fa
PrivKey3     d996f75ea9296f91b54ef57dc0b8210ccf4e497117532b712d58040f4ee82ac6
```
