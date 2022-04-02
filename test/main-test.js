const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const { prepareStand, createCondition, makeBet, getBlockTime, timeShift, tokens } = require("../utils/utils");

const ORACLE_CONDITION_START = 1000000;
const SCOPE_ID = 1;
const FEE = 1000000; // in decimals 10^9
const IPFS = "dummy";
const BET = tokens(100);
const ONE_HOUR = 3600;
const OUTCOMEWIN = 1;
const OUTCOMELOSE = 2;
const OUTCOMEINCORRECT = 3;

describe("TotoBetting test", function () {
  let owner, oracle, oracle2;
  let totoBetting, usdt;
  let time, condIDHash;

  let oracleCondID = ORACLE_CONDITION_START;

  before(async () => {
    [owner, oracle, oracle2, bettor, bettor2, addr1] = await ethers.getSigners();

    [totoBetting, usdt] = await prepareStand(ethers, owner, oracle, oracle2, bettor, bettor2, FEE);

    expect(await totoBetting.oracles(oracle.address)).to.be.equal(true);
  });
  describe("Oracle", function () {
    it("Should correctly add oracles", async () => {
      expect(await totoBetting.oracles(addr1.address)).to.be.equal(false);

      await totoBetting.addOracle(addr1.address);
      expect(await totoBetting.oracles(addr1.address)).to.be.equal(true);
    });
    it("Should correctly renounce oracles", async () => {
      await totoBetting.renounceOracle(addr1.address);
      expect(await totoBetting.oracles(addr1.address)).to.be.equal(false);
    });
  });
  describe("Conditions", async function () {
    beforeEach(async function () {
      oracleCondID++;
      time = await getBlockTime(ethers);
    });
    it("Should correctly create conditions", async () => {
      await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
      const condID = totoBetting.oracleConditionIDs(oracle.address, oracleCondID);

      const condition = await totoBetting.conditions(condID);
      expect(condition.timestamp).to.be.equal(time + ONE_HOUR);
    });
    it("Only oracle can interact with conditions", async () => {
      await expect(
        createCondition(totoBetting, addr1, oracleCondID, SCOPE_ID, [OUTCOMEWIN, OUTCOMELOSE], time + ONE_HOUR, IPFS)
      ).to.be.revertedWith("OnlyOracle()");

      await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      await expect(totoBetting.connect(addr1).cancelCondition(oracleCondID)).to.be.revertedWith("OnlyOracle()");
      await expect(totoBetting.connect(addr1).resolveCondition(oracleCondID, OUTCOMEWIN)).to.be.revertedWith(
        "OnlyOracle()"
      );
    });
    it("Should NOT create conditions that will begin soon", async () => {
      await expect(
        createCondition(totoBetting, oracle, oracleCondID, SCOPE_ID, [OUTCOMEWIN, OUTCOMELOSE], time + 1, IPFS)
      ).to.be.revertedWith("ConditionExpired()");
    });
    it("Should NOT create conditions with same outcomes", async () => {
      await expect(
        createCondition(totoBetting, oracle, oracleCondID, SCOPE_ID, [OUTCOMEWIN, OUTCOMEWIN], time + ONE_HOUR, IPFS)
      ).to.be.revertedWith("SameOutcomes()");
    });
    it("Should NOT create duplicate", async () => {
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
      await createCondition(
        totoBetting,
        oracle2,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
      await expect(
        createCondition(totoBetting, oracle, oracleCondID, SCOPE_ID, [OUTCOMEWIN, OUTCOMELOSE], time + ONE_HOUR, IPFS)
      ).to.be.revertedWith(`ConditionAlreadyCreated(${condIDHash})`);
    });
    it("Should NOT interact with nonexistent condition", async () => {
      const condIDNotExists = 2000000;
      await expect(makeBet(totoBetting, bettor, condIDNotExists, OUTCOMEWIN, BET)).to.be.revertedWith(
        `ConditionNotExists(${condIDNotExists})`
      );
      await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN)).to.be.revertedWith(
        `ConditionNotExists(0)`
      );
      await expect(totoBetting.connect(oracle).cancelCondition(oracleCondID)).to.be.revertedWith(
        `ConditionNotExists(0)`
      );
    });
    it("Should NOT resolve condition before it starts", async () => {
      let condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN)).to.be.revertedWith(
        `ConditionNotYetStarted(${condIDHash})`
      );
    });
    it("Should NOT resolve canceled condition", async () => {
      let condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN)).to.be.revertedWith(
        `ConditionNotYetStarted(${condIDHash})`
      );
    });
    it("Should NOT resolve condition before it starts", async () => {
      let condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN)).to.be.revertedWith(
        `ConditionNotYetStarted(${condIDHash})`
      );
    });
    it("Should NOT resolve condition with no bets on one of the outcomes", async () => {
      for (const outcome of [OUTCOMEWIN, OUTCOMELOSE]) {
        time = await getBlockTime(ethers);
        condIDHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondID,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        await makeBet(totoBetting, bettor, condIDHash, outcome, BET);

        timeShift(time + ONE_HOUR);
        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID++, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionCanceled(${condIDHash})`
        );
      }
    });
    it("Should NOT resolve condition with incorrect outcome", async () => {
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEINCORRECT)).to.be.revertedWith(
        "WrongOutcome()"
      );
    });
    it("Should NOT resolve condition twice", async () => {
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await expect(totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN)).to.be.revertedWith(
        `ConditionAlreadyResolved(${condIDHash})`
      );
    });
    it("Should NOT cancel resolved condition", async () => {
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await expect(totoBetting.connect(oracle).cancelCondition(oracleCondID)).to.be.revertedWith(
        `ConditionResolved(${condIDHash})`
      );
    });
  });
  describe("Bets", async function () {
    beforeEach(async function () {
      oracleCondID++;
      time = await getBlockTime(ethers);
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
    });
    it("Should send bet tokens to bettor proportionally bet amount", async () => {
      const tokenID = await totoBetting.getTokenID(condIDHash, OUTCOMEWIN);
      const balance = await totoBetting.balanceOf(bettor.address, tokenID);

      await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);

      expect(await totoBetting.balanceOf(bettor.address, tokenID)).to.be.equal(balance.add(BET));
    });
    it("Should NOT bet on started condition", async () => {
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      await expect(makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET)).to.be.revertedWith(
        `ConditionStarted(${condIDHash})`
      );
    });
    it(
      "Should NOT bet on condition that will begin soon  " + "if there are no bets on on of the outcomes",
      async () => {
        await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
        makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);

        timeShift(time + ONE_HOUR - 1);
        await expect(makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET)).to.be.revertedWith(
          `ConditionCanceled(${condIDHash})`
        );
      }
    );
    it("Should NOT bet on canceled condition", async () => {
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).cancelCondition(oracleCondID);

      await expect(makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET)).to.be.revertedWith(
        `ConditionCanceled(${condIDHash})`
      );
    });
    it("Should NOT bet on incorrect outcome", async () => {
      await expect(makeBet(totoBetting, bettor, condIDHash, OUTCOMEINCORRECT, BET)).to.be.revertedWith(
        "WrongOutcome()"
      );
    });
    it("Should NOT bet with no amount", async () => {
      await expect(makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, 0)).to.be.revertedWith("AmountMustNotBeZero()");
    });
    it("Should NOT bet with insufficient balance", async () => {
      const balance = await usdt.balanceOf(bettor.address);
      await expect(makeBet(totoBetting, addr1, condIDHash, OUTCOMEWIN, balance.add(1))).to.be.revertedWith(
        "transferFrom failed"
      );
    });
  });
  describe("Payouts", async function () {
    let tokenWin, tokenLose, balance;
    beforeEach(async function () {
      oracleCondID++;
      time = await getBlockTime(ethers);
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );
    });
    it("Should correctly calculate winning prize", async () => {
      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, tokens(100));
      tokenLose = await makeBet(totoBetting, bettor2, condIDHash, OUTCOMELOSE, tokens(200));
      await makeBet(totoBetting, bettor2, condIDHash, OUTCOMEWIN, tokens(400));

      balance = await usdt.balanceOf(bettor.address);
      const balance2 = await usdt.balanceOf(bettor2.address);

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      await totoBetting.connect(bettor2).withdrawPayout([tokenWin]);
      await totoBetting.connect(bettor2).withdrawPayout([tokenLose]);

      expect(await usdt.balanceOf(bettor.address)).to.be.equal(
        balance.add(
          BigNumber.from(tokens(140))
            .mul(10 ** 9 - FEE)
            .div(10 ** 9)
        )
      );
      expect(await usdt.balanceOf(bettor2.address)).to.be.equal(
        balance2.add(
          BigNumber.from(tokens(560))
            .mul(10 ** 9 - FEE)
            .div(10 ** 9)
        )
      );
    });
    it("Should nullify bet token balance after reward", async () => {
      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor2, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      expect(await totoBetting.balanceOf(bettor.address, tokenWin)).to.be.equal(0);
    });
    it("Should NOT reward in case of lose", async () => {
      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);
      await makeBet(totoBetting, bettor2, condIDHash, OUTCOMEWIN, BET);
      balance = await usdt.balanceOf(bettor.address);

      timeShift(time + ONE_HOUR);
      totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      expect(await usdt.balanceOf(bettor.address)).to.be.equal(balance);
    });
    it("Should NOT reward before condition ends", async () => {
      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await expect(totoBetting.connect(bettor).withdrawPayout([tokenWin])).to.be.revertedWith(
        `ConditionStillOn(${condIDHash})`
      );
    });
    it("Should NOT reward with zero bet token balance", async () => {
      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);
      await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, BET);

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await expect(totoBetting.connect(bettor2).withdrawPayout([tokenWin])).to.be.revertedWith(
        `ZeroBalance(${tokenWin})`
      );
    });
    it("Should refund bet if condition is canceled", async () => {
      balance = await usdt.balanceOf(bettor.address);
      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, BET);

      totoBetting.connect(oracle).cancelCondition(oracleCondID);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      expect(await usdt.balanceOf(bettor.address)).to.be.equal(balance);
    });
  });
  describe("DAO", async function () {
    it("Should correctly calculate DAO reward", async () => {
      await totoBetting.connect(owner).claimDAOReward();
      const balance = await usdt.balanceOf(owner.address);

      oracleCondID++;
      let time = await getBlockTime(ethers);
      let condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      let tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, tokens(100));
      let tokenLose = await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, tokens(200));

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).resolveCondition(oracleCondID, OUTCOMEWIN);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      await totoBetting.connect(bettor).withdrawPayout([tokenLose]);

      oracleCondID++;
      time = await getBlockTime(ethers);
      condIDHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondID,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      tokenWin = await makeBet(totoBetting, bettor, condIDHash, OUTCOMEWIN, tokens(400));
      tokenLose = await makeBet(totoBetting, bettor, condIDHash, OUTCOMELOSE, tokens(800));

      await totoBetting.connect(oracle).cancelCondition(oracleCondID);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      await totoBetting.connect(bettor).withdrawPayout([tokenLose]);

      await totoBetting.connect(owner).claimDAOReward();
      expect(await usdt.balanceOf(owner.address)).to.be.equal(
        balance.add(
          BigNumber.from(tokens(300))
            .mul(FEE)
            .div(10 ** 9)
        )
      );
    });
  });
});
