require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-contract-sizer");
require("hardhat-docgen");
require("hardhat-gas-reporter");

require("dotenv").config();

const ALCHEMY_API_KEY_RINKEBY = process.env.ALCHEMY_API_KEY_RINKEBY || "";
const RINKEBY_PRIVATE_KEY = process.env.RINKEBY_PRIVATE_KEY || "";
const MAINNET_PRIVATE_KEY = process.env.MAINNET_PRIVATE_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const exportNetworks = {
  hardhat:  {accounts: {
  accountsBalance: "1000000000000000000000000000"
}},
  ganache: {
    url: "http://127.0.0.1:8545",
    gasLimit: 6000000000,
    defaultBalanceEther: 10,
  },
};

if (ALCHEMY_API_KEY_RINKEBY != "" && RINKEBY_PRIVATE_KEY != "") {
  exportNetworks["rinkeby"] = {
    url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_API_KEY_RINKEBY}`,
    accounts: [`${RINKEBY_PRIVATE_KEY}`],
  };
}

if (MAINNET_PRIVATE_KEY != "") {
  exportNetworks["gnosis"] = {
    url: `https://rpc.gnosischain.com/`,
    accounts: [`${MAINNET_PRIVATE_KEY}`],
    gasPrice: 9000000000
  }
}

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
    ],
  },
  defaultNetwork: "hardhat",
  networks: exportNetworks,
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
  docgen: {
    path: "./docs",
    clear: false,
    only: ["PoolBetting"],
    runOnCompile: true,
  },
};
