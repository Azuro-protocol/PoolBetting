const { BigNumber } = require("@ethersproject/bignumber");

const prepareStand = async (ethers, owner, oracle, oracle2, fee) => {
  const mintableAmount = tokens(10 ** 9);
  // test USDT
  Usdt = await ethers.getContractFactory("TestERC20");
  usdt = await Usdt.deploy();
  await usdt.deployed();
  await usdt.mint(owner.address, mintableAmount);

  // toto betting core
  TotoBetting = await ethers.getContractFactory("TotoBetting");
  totoBetting = await upgrades.deployProxy(TotoBetting, [usdt.address, oracle.address, fee]);
  await totoBetting.deployed();

  // setting up
  await totoBetting.connect(owner).addOracle(oracle2.address);

  const approveAmount = tokens(10 ** 9);
  await usdt.approve(totoBetting.address, approveAmount);

  return [totoBetting, usdt];
};

const createCondition = async (totoBetting, oracle, oracleCondID_, scopeID, outcomes, timestamp, ipfsHash) => {
  const txCreate = await totoBetting
    .connect(oracle)
    .createCondition(oracleCondID_, scopeID, outcomes, timestamp, ethers.utils.formatBytes32String(ipfsHash));
  const conditionIDHash = await getConditionID_Hash(txCreate);

  return conditionIDHash;
};

const getConditionID_Hash = async (txCreateCondition) => {
  const eCondition = (await txCreateCondition.wait()).events.filter((x) => {
    return x.event == "ConditionCreated";
  });
  return eCondition[0].args.conditionID.toString();
};

const makeBet = async (totoBetting, bettor, conditionIDHash, outcome, amount) => {
  let txBet = await totoBetting.connect(bettor).makeBet(conditionIDHash, outcome, amount);
  let betTokenID = await getTokenID(txBet);

  return betTokenID;
};

const getTokenID = async (txBet) => {
  let eBet = (await txBet.wait()).events.filter((x) => {
    return x.event == "NewBet";
  });
  return eBet[0].args[1];
};

async function getBlockTime(ethers) {
  const blockNumBefore = await ethers.provider.getBlockNumber();
  const blockBefore = await ethers.provider.getBlock(blockNumBefore);
  const time = blockBefore.timestamp;
  return time;
}

async function timeShift(time) {
  await network.provider.send("evm_setNextBlockTimestamp", [time]);
  await network.provider.send("evm_mine");
}

function timeout(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function tokens(val) {
  return BigNumber.from(val).mul(BigNumber.from("10").pow(18)).toString();
}

function randomTokens(power) {
  power += 18;
  let random =
    Math.random().toString().slice(2, 18) +
    Math.random()
      .toString()
      .slice(2, power - 14);
  return BigNumber.from(random).add(1);
}

module.exports = {
  prepareStand,
  createCondition,
  makeBet,
  getBlockTime,
  timeShift,
  timeout,
  tokens,
  randomTokens,
};
