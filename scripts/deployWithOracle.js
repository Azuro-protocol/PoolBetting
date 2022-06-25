const { ethers } = require("hardhat");
const hre = require("hardhat");

const { tokens, timeout, getBlockTime, createCondition } = require("../utils/utils");

const FEE = 10000000; // 1%
const EVENT_START_IN = 3600; // 1 hour
const SCOPE_ID = 0; // game id
const ORACLES = [
  "0x0D62B886234EA4dC9bd86FaB239578DcD0075fb0",
  "0x2c33fEe397eEA9a3573A31a2Ea926424E35584a1",
  "0x628d2714F912aaB37e00304B5fF0283BE7DFf75f",
  "0x834DD1699F7ed641b8FED8A57D1ad48A9B6Adb4E",
];

let TEST_WALLET = [];
TEST_WALLET.push(process.env.TEST_WALLET1);
TEST_WALLET.push(process.env.TEST_WALLET2);
TEST_WALLET.push(process.env.TEST_WALLET3);

async function main() {
  const [deployer] = await ethers.getSigners();
  const oracle = deployer;

  let oracleCondID = 0;
  let wxDAI, totoBetting, totoBettingImpl, testWallet;

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

  // TotoBetting
  {
    const TotoBetting = await ethers.getContractFactory("TotoBetting");
    totoBetting = await upgrades.deployProxy(TotoBetting, [wxDAI.address, oracle.address, FEE]);
    console.log("TotoBetting proxy deployed to:", totoBetting.address);
    await timeout(TIME_OUT);
    await totoBetting.deployed();
    await timeout(TIME_OUT);
    totoBettingImpl = await upgrades.erc1967.getImplementationAddress(totoBetting.address);
    await totoBettingImpl.initialize();
    console.log("TotoBetting deployed to:", totoBettingImpl);
    console.log();
  }

  // settings
  {
    const approveAmount = tokens(999_999_999);
    await wxDAI.approve(totoBetting.address, approveAmount);
    await timeout(TIME_OUT);
    console.log("Approve done", approveAmount.toString());
    console.log();

    time = await getBlockTime(ethers);

    for (const iterator of Array(3).keys()) {
      oracleCondID++;
      await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [oracleCondID, oracleCondID + 1],
        time + EVENT_START_IN,
        oracleCondID
      );

      await timeout(TIME_OUT);
      console.log("Condition %s created", oracleCondID);
    }
    console.log();

    for (const iterator of Array(3).keys()) {
      testWallet = TEST_WALLET[iterator];
      await wxDAI.connect(deployer).approve(testWallet, tokens(10_000_000));
      await deployer.connect(wxDAI).transfer(testWallet, tokens(10_000_000));
      await timeout(TIME_OUT);
      console.log("10 000 000 wxDAI sent to %s", TEST_WALLET[iterator]);
    }
    console.log();

    for (const iterator of ORACLES.keys()) {
      await totoBetting.addOracle(ORACLES[iterator]);
      await timeout(TIME_OUT);
    }
    console.log("Oracles:", ORACLES);
  }

  // verification
  if (chainId != 0x7a69) {
    await hre.run("verify:verify", {
      address: totoBettingImpl,
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
