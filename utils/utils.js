const { BigNumber } = require("@ethersproject/bignumber");
const { ethers } = require("hardhat");

const prepareStand = async (ethers, owner, oracle, oracle2, fee) => {
  // test wxDai
  WXDAI = await ethers.getContractFactory("WETH9");
  wxDAI = await WXDAI.deploy();
  await wxDAI.deployed();
  await owner.sendTransaction({ to: wxDAI.address, value: ethers.utils.parseEther("10000000") });

  // toto betting core
  TotoBetting = await ethers.getContractFactory("TotoBetting");
  totoBetting = await upgrades.deployProxy(TotoBetting, [wxDAI.address, oracle.address, fee]);
  await totoBetting.deployed();

  // setting up
  await totoBetting.connect(owner).addOracle(oracle2.address);

  const approveAmount = tokens(10 ** 9);
  await wxDAI.approve(totoBetting.address, approveAmount);

  return [totoBetting, wxDAI];
};

const createCondition = async (totoBetting, oracle, oracleCondId_, outcomes, timestamp, ipfsHash) => {
  const txCreate = await totoBetting
    .connect(oracle)
    .createCondition(oracleCondId_, outcomes, timestamp, ethers.utils.formatBytes32String(ipfsHash));
  const conditionIdHash = await getConditionId_Hash(txCreate);

  return conditionIdHash;
};

const getConditionId_Hash = async (txCreateCondition) => {
  const eCondition = (await txCreateCondition.wait()).events.filter((x) => {
    return x.event == "ConditionCreated";
  });
  return eCondition[0].args.conditionId.toString();
};

const makeBet = async (totoBetting, bettor, conditionIdHash, outcome, amount) => {
  let txBet = await totoBetting.connect(bettor).bet(conditionIdHash, outcome, amount);
  let betTokenId = await getTokenId(txBet);

  return betTokenId;
};

const makeBetNative = async (totoBetting, bettor, conditionIdHash, outcome, amount) => {
  let txBet = await totoBetting.connect(bettor).betNative(conditionIdHash, outcome, {
    value: BigNumber.from(amount),
  });
  let betTokenId = await getTokenId(txBet);

  return betTokenId;
};

const getTokenId = async (txBet) => {
  let eBet = (await txBet.wait()).events.filter((x) => {
    return x.event == "NewBet";
  });
  return eBet[0].args[1];
};

const getUsedGas = async (tx) => {
  const receipt = await tx.wait();
  const gas = BigInt(receipt.cumulativeGasUsed) * BigInt(receipt.effectiveGasPrice);
  return gas;
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
  makeBetNative,
  getUsedGas,
  getBlockTime,
  timeShift,
  timeout,
  tokens,
  randomTokens,
};
