const hre = require("hardhat");
const { ethers } = require("hardhat");
const { timeout } = require("../utils/utils");

const MULTIPLIER = 10 ** 12;
const FEE = MULTIPLIER * 0.01; // 1%

async function main() {
  const [deployer] = await ethers.getSigners();
  const oracle = deployer;

  let tokenAddress, pullBetting, pullBettingImpl;

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

  // PullBetting
  {
    const PullBetting = await ethers.getContractFactory("PullBetting");
    pullBetting = await upgrades.deployProxy(PullBetting, [tokenAddress, oracle.address, FEE]);
    console.log("PullBetting proxy deployed to:", pullBetting.address);
    await timeout(TIME_OUT);
    await pullBetting.deployed();
    await timeout(TIME_OUT);
    pullBettingImplAddress = await upgrades.erc1967.getImplementationAddress(pullBetting.address);
    const pullBettingImpl = await PullBetting.attach(pullBettingImplAddress);
    await pullBettingImpl.initialize(ethers.Wallet.createRandom().address, ethers.constants.AddressZero, 0);
    console.log("PullBetting deployed to:", pullBettingImplAddress);
    console.log();
  }

  // verification
  if (chainId != 0x7a69) {
    await hre.run("verify:verify", {
      address: pullBettingImplAddress,
      constructorArguments: [],
    });
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
