const { ethers } = require("hardhat");
const hre = require("hardhat");

const { tokens, timeout, getBlockTime, createCondition } = require("../utils/utils");

const FEE = 10000000; // 1%
const EVENT_START_IN = 3600; // 1 hour

let TEST_WALLET = [];
TEST_WALLET.push(process.env.TEST_WALLET1);
TEST_WALLET.push(process.env.TEST_WALLET2);
TEST_WALLET.push(process.env.TEST_WALLET3);

async function main() {
  const [deployer] = await ethers.getSigners();

  let wxDAI, poolBetting, poolBettingImpl, testWallet;

  console.log("Deployer wallet: ", deployer.address);
  console.log("Deployer balance:", (await deployer.getBalance()).toString());
  console.log();

  const chainId = await hre.network.provider.send("eth_chainId");
  // hardhat => 800
  // kovan => 8000
  // rinkeby => 20000
  // sokol => 5000 (0x4D)
  const TIME_OUT = chainId == 0x7a69 ? 800 : chainId == 0x2a ? 8000 : chainId == 0x4d ? 5000 : 20000;

  // WXDAI
  {
    const WXDAI = await ethers.getContractFactory("WETH9");
    wxDAI = await WXDAI.deploy();
    await wxDAI.deployed();
    await timeout(TIME_OUT);
    console.log("wxDAI deployed to:", wxDAI.address);
    await deployer.sendTransaction({ to: wxDAI.address, value: tokens(800_000_000) });
    await timeout(TIME_OUT);
  }

  // PoolBetting
  {
    const PoolBetting = await ethers.getContractFactory("PoolBetting");
    poolBetting = await upgrades.deployProxy(PoolBetting, [wxDAI.address, FEE]);
    console.log("PoolBetting proxy deployed to:", poolBetting.address);
    await timeout(TIME_OUT);
    await poolBetting.deployed();
    await timeout(TIME_OUT);
    poolBettingImpl = await upgrades.erc1967.getImplementationAddress(poolBetting.address);
    await poolBettingImpl.initialize();
    console.log("PoolBetting deployed to:", poolBettingImpl);
    console.log();
  }

  // settings
  {
    const approveAmount = tokens(999_999_999);
    await wxDAI.approve(poolBetting.address, approveAmount);
    await timeout(TIME_OUT);
    console.log("Approve done", approveAmount.toString());
    console.log();
  }

  // verification
  if (chainId != 0x7a69) {
    await hre.run("verify:verify", {
      address: poolBettingImpl,
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
