const hre = require("hardhat");
const { ethers } = require("hardhat");
const { timeout } = require("../utils/utils");

const MULTIPLIER = 10 ** 12;
const FEE = MULTIPLIER * 0.01; // 1%

async function main() {
  const [deployer] = await ethers.getSigners();

  let tokenAddress, poolBetting;

  console.log("Deployer wallet: ", deployer.address);
  console.log("Deployer balance:", (await deployer.getBalance()).toString());
  console.log();

  const chainId = await hre.network.provider.send("eth_chainId");
  // hardhat => 800
  // kovan => 8000
  // rinkeby => 20000
  // sokol => 5000 (0x4D)
  const TIME_OUT = chainId == 0x7a69 ? 800 : chainId == 0x2a ? 8000 : chainId == 0x4d ? 5000 : 20000;

  // Token
  {
    tokenAddress = process.env.TOKEN_ADDRESS;
  }

  // PoolBetting
  {
    const PoolBetting = await ethers.getContractFactory("PoolBetting");
    poolBetting = await upgrades.deployProxy(PoolBetting, [tokenAddress, FEE]);
    console.log("PoolBetting proxy deployed to:", poolBetting.address);
    await timeout(TIME_OUT);
    await poolBetting.deployed();
    await timeout(TIME_OUT);
    poolBettingImplAddress = await upgrades.erc1967.getImplementationAddress(poolBetting.address);
    const poolBettingImpl = await PoolBetting.attach(poolBettingImplAddress);
    await poolBettingImpl.initialize(ethers.Wallet.createRandom().address, 0);
    console.log("PoolBetting deployed to:", poolBettingImplAddress);
    console.log();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
