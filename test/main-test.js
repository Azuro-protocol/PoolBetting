const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const {
  prepareStand,
  createCondition,
  makeBet,
  makeBetNative,
  getUsedGas,
  getBlockTime,
  timeShift,
  tokens,
  randomTokens,
} = require("../utils/utils");

const ORACLE_CONDITION_START = 1000000;
const SCOPE_ID = 1;
const FEE = 10 ** 6; // in decimals 10^9
const IPFS = "dummy";
const BET = tokens(100);
const ONE_HOUR = 3600;
const OUTCOMEWIN = 1;
const OUTCOMELOSE = 2;
const OUTCOMEINCORRECT = 3;

const TRIES = 5;
const MIN_BETTORS = 3; // >= 2
const MAX_BETTORS = 16;

const prepareBettors = async (totoBetting, wxDAI, n) => {
  let bettors = [],
    bettor;
  [donor] = await ethers.getSigners();
  for (let k = 0; k < n; k++) {
    bettor = await ethers.Wallet.createRandom();
    bettor = bettor.connect(ethers.provider);
    await donor.sendTransaction({ to: bettor.address, value: ethers.utils.parseEther("10000000") });
    await bettor.sendTransaction({ to: wxDAI.address, value: tokens(5000000) });
    await wxDAI.connect(bettor).approve(totoBetting.address, tokens(10000000));
    bettors.push(bettor);
  }
  return bettors;
};

describe("TotoBetting test", function () {
  let owner, oracle, oracle2, bettors, bettor, bettor2;
  let totoBetting, wxDAI;
  let time, condIdHash;

  let oracleCondId = ORACLE_CONDITION_START;

  before(async () => {
    [owner, oracle, oracle2, addr1] = await ethers.getSigners();

    [totoBetting, wxDAI] = await prepareStand(ethers, owner, oracle, oracle2, FEE);

    bettors = await prepareBettors(totoBetting, wxDAI, MAX_BETTORS);
    bettor = bettors[0];
    bettor2 = bettors[1];
  });
  describe("Oracle test", function () {
    it("Add and renounce oracle", async () => {
      expect(await totoBetting.oracles(addr1.address)).to.be.equal(false);

      await totoBetting.addOracle(addr1.address);
      expect(await totoBetting.oracles(addr1.address)).to.be.equal(true);

      await totoBetting.renounceOracle(addr1.address);
      expect(await totoBetting.oracles(addr1.address)).to.be.equal(false);
    });
  });
  describe("Betting test", function () {
    it("Withdraw reward", async () => {
      let nBettors;
      let bets = [],
        betTokens = [];
      let totalNetBets, totalWinBets;
      let bettor, balance, bet, outcome, betToken;

      for (let i = 0; i < TRIES; i++) {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);
        totalNetBets = totalWinBets = BigNumber.from(0);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = randomTokens(2);
          totalNetBets = totalNetBets.add(bet);
          if (outcome == OUTCOMEWIN) {
            totalWinBets = totalWinBets.add(bet);
          }
          bets[k] = bet;

          betToken = await makeBet(totoBetting, bettor, condIdHash, outcome, bet);
          expect(await totoBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;
        }

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          balance = await wxDAI.balanceOf(bettor.address);
          betToken = betTokens[k];
          await totoBetting.connect(bettor).withdrawPayout([betToken]);
          if (betToken.eq(betTokens[0])) {
            expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(
              balance.add(
                totalNetBets
                  .mul(bets[k])
                  .div(totalWinBets)
                  .mul(10 ** 9 - FEE)
                  .div(10 ** 9)
              )
            );
          } else {
            expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(balance);
          }
        }
      }
    });
    it("Withdraw reward but with unbalanced bets", async () => {
      let nBettors;
      let bets = [],
        betTokens = [];
      let totalNetBets, totalWinBets;
      let bettor, balance, bet, outcome, betToken;

      for (let i = 0; i < TRIES; i++) {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);
        totalNetBets = totalWinBets = BigNumber.from(0);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = Math.random() > 1 / 2 ? randomTokens(2) : Math.floor(Math.random() * 5 + 1);
          totalNetBets = totalNetBets.add(bet);
          if (outcome == OUTCOMEWIN) {
            totalWinBets = totalWinBets.add(bet);
          }
          bets[k] = bet;

          betToken = await makeBet(totoBetting, bettor, condIdHash, outcome, bet);
          expect(await totoBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;
        }

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          balance = await wxDAI.balanceOf(bettor.address);
          betToken = betTokens[k];
          await totoBetting.connect(bettor).withdrawPayout([betToken]);
          if (betToken.eq(betTokens[0])) {
            expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(
              balance.add(
                totalNetBets
                  .mul(bets[k])
                  .div(totalWinBets)
                  .mul(10 ** 9 - FEE)
                  .div(10 ** 9)
              )
            );
          } else {
            expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(balance);
          }
        }
      }
    });
    it("Withdraw reward but from several conditions", async () => {
      let bets = [],
        betTokens = [],
        winTokens = [];
      let nConditions;
      let bettor, balance, reward, bet, outcome, betToken;

      for (let i = 0; i < TRIES; i++) {
        nConditions = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);
        bettor = bettors[0];
        reward = BigNumber.from(0);

        for (let k = 0; k < nConditions; k++) {
          oracleCondId++;
          time = await getBlockTime(ethers);
          condIdHash = await createCondition(
            totoBetting,
            oracle,
            oracleCondId,
            SCOPE_ID,
            [OUTCOMEWIN, OUTCOMELOSE],
            time + ONE_HOUR,
            IPFS
          );

          winTokens[k] = await makeBet(totoBetting, bettor2, condIdHash, OUTCOMEWIN, BET);
          await makeBet(totoBetting, bettor2, condIdHash, OUTCOMELOSE, BET);

          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = randomTokens(2);
          bets[k] = bet;

          betToken = await makeBet(totoBetting, bettor, condIdHash, outcome, bet);
          expect(await totoBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;

          timeShift(time + ONE_HOUR);
          await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);
        }

        balance = await wxDAI.balanceOf(bettor.address);

        await totoBetting.connect(bettor).withdrawPayout(betTokens.slice(0, nConditions));

        for (let k = 0; k < nConditions; k++) {
          if (betTokens[k].eq(winTokens[k])) {
            bet = BigNumber.from(bets[k]);
            reward = reward.add(bet.add(BigNumber.from(BET).mul(2)).mul(bet).div(bet.add(BET)));
          }
        }
        reward = reward.mul(10 ** 9 - FEE).div(10 ** 9);
        expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(balance.add(reward));
      }
    });
    it("Make bets and withdraw payout in native token", async () => {
      let nBettors;
      let bets = [],
        betTokens = [];
      let totalNetBets, totalWinBets;
      let bettor, balance, bet, outcome, betToken;
      let txWithdraw, usedGas;

      for (let i = 0; i < TRIES; i++) {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);
        totalNetBets = totalWinBets = BigNumber.from(0);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = randomTokens(2);
          totalNetBets = totalNetBets.add(bet);
          if (outcome == OUTCOMEWIN) {
            totalWinBets = totalWinBets.add(bet);
          }
          bets[k] = bet;

          betToken = await makeBetNative(totoBetting, bettor, condIdHash, outcome, bet);
          expect(await totoBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;
        }

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          balance = await ethers.provider.getBalance(bettor.address);
          betToken = betTokens[k];
          txWithdraw = await totoBetting.connect(bettor).withdrawPayoutNative([betToken]);
          usedGas = await getUsedGas(txWithdraw);
          if (betToken.eq(betTokens[0])) {
            expect(await ethers.provider.getBalance(bettor.address)).to.be.equal(
              balance
                .add(
                  totalNetBets
                    .mul(bets[k])
                    .div(totalWinBets)
                    .mul(10 ** 9 - FEE)
                    .div(10 ** 9)
                )
                .sub(usedGas)
            );
          } else {
            expect(await ethers.provider.getBalance(bettor.address)).to.be.equal(balance.sub(usedGas));
          }
        }
      }
    });
    it("Get refund for canceled condition", async () => {
      let nBettors;
      let balances = [],
        bets = [],
        betTokens = [];
      let bet, outcome;

      for (let i = 0; i < TRIES; i++) {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);

        for (let k = 0; k < nBettors; k++) {
          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = randomTokens(2);
          bets[k] = bet;
          balances[k] = await wxDAI.balanceOf(bettors[k].address);

          betTokens[k] = await makeBet(totoBetting, bettors[k], condIdHash, outcome, bet);
        }

        await totoBetting.connect(oracle).cancelCondition(oracleCondId);

        for (let k = 0; k < nBettors; k++) {
          await totoBetting.connect(bettors[k]).withdrawPayout([betTokens[k]]);

          expect(await wxDAI.balanceOf(bettors[k].address)).to.be.equal(balances[k]);
        }
      }
    });
    it("Get refund for expired condition", async () => {
      let nBettors;
      let balances = [],
        bets = [];
      let bet,
        betToken,
        outcome = OUTCOMEWIN;

      for (let i = 0; i < TRIES; i++) {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);

        for (let k = 0; k < nBettors; k++) {
          bet = randomTokens(2);
          bets[k] = bet;
          balances[k] = await wxDAI.balanceOf(bettors[k].address);

          betToken = await makeBet(totoBetting, bettors[k], condIdHash, outcome, bet);
        }

        timeShift(time + ONE_HOUR);

        for (let k = 0; k < nBettors; k++) {
          await totoBetting.connect(bettors[k]).withdrawPayout([betToken]);

          expect(await wxDAI.balanceOf(bettors[k].address)).to.be.equal(balances[k]);
        }
      }
    });
  });
  describe("DAO", async function () {
    it("Withdraw DAO reward", async () => {
      await totoBetting.connect(owner).claimDAOReward();
      const balance = await wxDAI.balanceOf(owner.address);

      oracleCondId++;
      let time = await getBlockTime(ethers);
      let condIdHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondId,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      let tokenWin = await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, tokens(100));
      let tokenLose = await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, tokens(200));

      timeShift(time + ONE_HOUR);
      await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      await totoBetting.connect(bettor).withdrawPayout([tokenLose]);

      oracleCondId++;
      time = await getBlockTime(ethers);
      condIdHash = await createCondition(
        totoBetting,
        oracle,
        oracleCondId,
        SCOPE_ID,
        [OUTCOMEWIN, OUTCOMELOSE],
        time + ONE_HOUR,
        IPFS
      );

      tokenWin = await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, tokens(400));
      tokenLose = await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, tokens(800));

      await totoBetting.connect(oracle).cancelCondition(oracleCondId);

      await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
      await totoBetting.connect(bettor).withdrawPayout([tokenLose]);

      await totoBetting.connect(owner).claimDAOReward();

      expect(await wxDAI.balanceOf(owner.address)).to.be.equal(
        balance.add(
          BigNumber.from(tokens(300))
            .mul(FEE)
            .div(10 ** 9)
        )
      );
    });
  });
  describe("Check restrictions", async function () {
    describe("Conditions", async function () {
      beforeEach(async function () {
        oracleCondId++;
        time = await getBlockTime(ethers);
      });
      it("Only oracle can interact with conditions", async () => {
        await expect(
          createCondition(totoBetting, addr1, oracleCondId, SCOPE_ID, [OUTCOMEWIN, OUTCOMELOSE], time + ONE_HOUR, IPFS)
        ).to.be.revertedWith("OnlyOracle()");

        await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        await expect(totoBetting.connect(addr1).cancelCondition(oracleCondId)).to.be.revertedWith("OnlyOracle()");
        await expect(totoBetting.connect(addr1).resolveCondition(oracleCondId, OUTCOMEWIN)).to.be.revertedWith(
          "OnlyOracle()"
        );
      });
      it("Should NOT create conditions that will begin soon", async () => {
        await expect(
          createCondition(totoBetting, oracle, oracleCondId, SCOPE_ID, [OUTCOMEWIN, OUTCOMELOSE], time + 1, IPFS)
        ).to.be.revertedWith("ConditionExpired()");
      });
      it("Should NOT create conditions with same outcomes", async () => {
        await expect(
          createCondition(totoBetting, oracle, oracleCondId, SCOPE_ID, [OUTCOMEWIN, OUTCOMEWIN], time + ONE_HOUR, IPFS)
        ).to.be.revertedWith("SameOutcomes()");
      });
      it("Should NOT create duplicate", async () => {
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );
        await createCondition(
          totoBetting,
          oracle2,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );
        await expect(
          createCondition(totoBetting, oracle, oracleCondId, SCOPE_ID, [OUTCOMEWIN, OUTCOMELOSE], time + ONE_HOUR, IPFS)
        ).to.be.revertedWith(`ConditionAlreadyCreated(${condIdHash})`);
      });
      it("Should NOT interact with nonexistent condition", async () => {
        const condIdNotExists = 2000000;
        await expect(makeBet(totoBetting, bettor, condIdNotExists, OUTCOMEWIN, BET)).to.be.revertedWith(
          `ConditionNotExists(${condIdNotExists})`
        );
        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotExists(0)`
        );
        await expect(totoBetting.connect(oracle).cancelCondition(oracleCondId)).to.be.revertedWith(
          `ConditionNotExists(0)`
        );
      });
      it("Should NOT resolve condition before it starts", async () => {
        let condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotYetStarted(${condIdHash})`
        );
      });
      it("Should NOT resolve canceled condition", async () => {
        let condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotYetStarted(${condIdHash})`
        );
      });
      it("Should NOT resolve condition before it starts", async () => {
        let condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotYetStarted(${condIdHash})`
        );
      });
      it("Should NOT resolve condition with no bets on one of the outcomes", async () => {
        for (const outcome of [OUTCOMEWIN, OUTCOMELOSE]) {
          time = await getBlockTime(ethers);
          condIdHash = await createCondition(
            totoBetting,
            oracle,
            oracleCondId,
            SCOPE_ID,
            [OUTCOMEWIN, OUTCOMELOSE],
            time + ONE_HOUR,
            IPFS
          );

          await makeBet(totoBetting, bettor, condIdHash, outcome, BET);

          timeShift(time + ONE_HOUR);
          await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId++, OUTCOMEWIN)).to.be.revertedWith(
            `ConditionCanceled(${condIdHash})`
          );
        }
      });
      it("Should NOT resolve condition with incorrect outcome", async () => {
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );

        await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEINCORRECT)).to.be.revertedWith(
          "WrongOutcome()"
        );
      });
      it("Should NOT resolve condition twice", async () => {
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        await expect(totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionAlreadyResolved(${condIdHash})`
        );
      });
      it("Should NOT cancel resolved condition", async () => {
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        await expect(totoBetting.connect(oracle).cancelCondition(oracleCondId)).to.be.revertedWith(
          `ConditionResolved(${condIdHash})`
        );
      });
    });
    describe("Bets", async function () {
      beforeEach(async function () {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );
      });
      it("Should NOT bet on started condition", async () => {
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await expect(makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET)).to.be.revertedWith(
          `ConditionStarted(${condIdHash})`
        );
      });
      it("Should NOT bet on condition that will begin soon if there are no bets on on of the outcomes", async () => {
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);

        timeShift(time + ONE_HOUR - 1);
        await expect(makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET)).to.be.revertedWith(
          `ConditionCanceled(${condIdHash})`
        );
      });
      it("Should NOT bet on canceled condition", async () => {
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).cancelCondition(oracleCondId);

        await expect(makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET)).to.be.revertedWith(
          `ConditionCanceled(${condIdHash})`
        );
      });
      it("Should NOT bet on incorrect outcome", async () => {
        await expect(makeBet(totoBetting, bettor, condIdHash, OUTCOMEINCORRECT, BET)).to.be.revertedWith(
          "WrongOutcome()"
        );
      });
      it("Should NOT bet with no amount", async () => {
        await expect(makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, 0)).to.be.revertedWith(
          "AmountMustNotBeZero()"
        );
      });
      it("Should NOT bet with insufficient balance", async () => {
        const balance = await wxDAI.balanceOf(bettor.address);
        await expect(makeBet(totoBetting, addr1, condIdHash, OUTCOMEWIN, balance.add(1))).to.be.revertedWith(
          "transferFrom failed"
        );
      });
    });
    describe("Payouts", async function () {
      let tokenWin, tokenLose, balance;
      beforeEach(async function () {
        oracleCondId++;
        time = await getBlockTime(ethers);
        condIdHash = await createCondition(
          totoBetting,
          oracle,
          oracleCondId,
          SCOPE_ID,
          [OUTCOMEWIN, OUTCOMELOSE],
          time + ONE_HOUR,
          IPFS
        );
      });
      it("Should NOT reward in case of lose", async () => {
        tokenWin = await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);
        await makeBet(totoBetting, bettor2, condIdHash, OUTCOMEWIN, BET);
        balance = await wxDAI.balanceOf(bettor.address);

        timeShift(time + ONE_HOUR);
        totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        await totoBetting.connect(bettor).withdrawPayout([tokenWin]);
        expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(balance);
      });
      it("Should NOT reward before condition ends", async () => {
        tokenWin = await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await expect(totoBetting.connect(bettor).withdrawPayout([tokenWin])).to.be.revertedWith(
          `ConditionStillOn(${condIdHash})`
        );
      });
      it("Should NOT reward with zero bet token balance", async () => {
        tokenWin = await makeBet(totoBetting, bettor, condIdHash, OUTCOMEWIN, BET);
        await makeBet(totoBetting, bettor, condIdHash, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await totoBetting.connect(oracle).resolveCondition(oracleCondId, OUTCOMEWIN);

        await expect(totoBetting.connect(bettor2).withdrawPayout([tokenWin])).to.be.revertedWith(
          `ZeroBalance(${tokenWin})`
        );
      });
    });
  });
});
