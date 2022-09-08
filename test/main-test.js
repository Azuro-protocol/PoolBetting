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

const MULTIPLIER = 10 ** 12;

const FEE = MULTIPLIER * 0.01; // 1%
const IPFS = ethers.utils.formatBytes32String("ipfs");
const BET = tokens(100);
const ONE_HOUR = 3600;
const ONE_MINUTE = 60;
const OUTCOMEWIN = 1;
const OUTCOMELOSE = 2;
const OUTCOMEINCORRECT = 3;

const TRIES = 5;
const MIN_BETTORS = 3; // >= 2
const MAX_BETTORS = 16;

const prepareBettors = async (poolBetting, wxDAI, n) => {
  let bettors = [],
    bettor;
  [donor] = await ethers.getSigners();
  for (let k = 0; k < n; k++) {
    bettor = await ethers.Wallet.createRandom();
    bettor = bettor.connect(ethers.provider);
    await donor.sendTransaction({ to: bettor.address, value: ethers.utils.parseEther("10000000") });
    await bettor.sendTransaction({ to: wxDAI.address, value: tokens(5000000) });
    await wxDAI.connect(bettor).approve(poolBetting.address, tokens(10000000));
    bettors.push(bettor);
  }
  return bettors;
};

describe("PoolBetting test", function () {
  let owner, oracle, oracle2, bettors, bettor, bettor2;
  let poolBetting, wxDAI;
  let time, conditionId;

  before(async () => {
    [owner, oracle, oracle2, addr1] = await ethers.getSigners();

    [poolBetting, wxDAI] = await prepareStand(ethers, owner, FEE);

    bettors = await prepareBettors(poolBetting, wxDAI, MAX_BETTORS);
    bettor = bettors[0];
    bettor2 = bettors[1];
  });
  describe("Betting test", function () {
    it("Withdraw reward", async () => {
      let nBettors;
      let bets = [],
        betTokens = [];
      let totalNetBets, totalWinBets;
      let bettor, balance, bet, outcome, betToken;

      for (let i = 0; i < TRIES; i++) {
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

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

          betToken = await makeBet(poolBetting, bettor, conditionId, outcome, bet);
          expect(await poolBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;
        }

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          balance = await wxDAI.balanceOf(bettor.address);
          betToken = betTokens[k];
          await poolBetting.connect(bettor).withdrawPayout([betToken]);
          if (betToken.eq(betTokens[0])) {
            expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(
              balance.add(
                totalNetBets
                  .mul(bets[k])
                  .div(totalWinBets)
                  .mul(MULTIPLIER - FEE)
                  .div(MULTIPLIER)
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
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

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

          betToken = await makeBet(poolBetting, bettor, conditionId, outcome, bet);
          expect(await poolBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;
        }

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          balance = await wxDAI.balanceOf(bettor.address);
          betToken = betTokens[k];
          await poolBetting.connect(bettor).withdrawPayout([betToken]);
          if (betToken.eq(betTokens[0])) {
            expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(
              balance.add(
                totalNetBets
                  .mul(bets[k])
                  .div(totalWinBets)
                  .mul(MULTIPLIER - FEE)
                  .div(MULTIPLIER)
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
          time = await getBlockTime(ethers);
          conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

          winTokens[k] = await makeBet(poolBetting, bettor2, conditionId, OUTCOMEWIN, BET);
          await makeBet(poolBetting, bettor2, conditionId, OUTCOMELOSE, BET);

          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = randomTokens(2);
          bets[k] = bet;

          betToken = await makeBet(poolBetting, bettor, conditionId, outcome, bet);
          expect(await poolBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;

          timeShift(time + ONE_HOUR);
          await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);
        }

        balance = await wxDAI.balanceOf(bettor.address);

        await poolBetting.connect(bettor).withdrawPayout(betTokens.slice(0, nConditions));

        for (let k = 0; k < nConditions; k++) {
          if (betTokens[k].eq(winTokens[k])) {
            bet = BigNumber.from(bets[k]);
            reward = reward.add(bet.add(BigNumber.from(BET).mul(2)).mul(bet).div(bet.add(BET)));
          }
        }
        reward = reward.mul(MULTIPLIER - FEE).div(MULTIPLIER);
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
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

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

          betToken = await makeBetNative(poolBetting, bettor, conditionId, outcome, bet);
          expect(await poolBetting.balanceOf(bettor.address, betToken)).to.be.equal(bet);
          betTokens[k] = betToken;
        }

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        for (let k = 0; k < nBettors; k++) {
          bettor = bettors[k];
          balance = await ethers.provider.getBalance(bettor.address);
          betToken = betTokens[k];
          txWithdraw = await poolBetting.connect(bettor).withdrawPayoutNative([betToken]);
          usedGas = await getUsedGas(txWithdraw);
          if (betToken.eq(betTokens[0])) {
            expect(await ethers.provider.getBalance(bettor.address)).to.be.equal(
              balance
                .add(
                  totalNetBets
                    .mul(bets[k])
                    .div(totalWinBets)
                    .mul(MULTIPLIER - FEE)
                    .div(MULTIPLIER)
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
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);

        for (let k = 0; k < nBettors; k++) {
          outcome = k == 0 ? OUTCOMEWIN : k == 1 ? OUTCOMELOSE : Math.random() > 1 / 2 ? OUTCOMEWIN : OUTCOMELOSE;
          bet = randomTokens(2);
          bets[k] = bet;
          balances[k] = await wxDAI.balanceOf(bettors[k].address);

          betTokens[k] = await makeBet(poolBetting, bettors[k], conditionId, outcome, bet);
        }

        await poolBetting.connect(oracle).cancelCondition(conditionId);

        for (let k = 0; k < nBettors; k++) {
          await poolBetting.connect(bettors[k]).withdrawPayout([betTokens[k]]);

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
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        nBettors = Math.floor(Math.random() * (MAX_BETTORS - MIN_BETTORS + 1) + MIN_BETTORS);

        for (let k = 0; k < nBettors; k++) {
          bet = randomTokens(2);
          bets[k] = bet;
          balances[k] = await wxDAI.balanceOf(bettors[k].address);

          betToken = await makeBet(poolBetting, bettors[k], conditionId, outcome, bet);
        }

        timeShift(time + ONE_HOUR);

        for (let k = 0; k < nBettors; k++) {
          await poolBetting.connect(bettors[k]).withdrawPayout([betToken]);

          expect(await wxDAI.balanceOf(bettors[k].address)).to.be.equal(balances[k]);
        }
      }
    });
  });
  describe("DAO", async function () {
    it("Withdraw DAO reward", async () => {
      await poolBetting.connect(owner).claimDaoReward();
      const balance = await wxDAI.balanceOf(owner.address);

      let time = await getBlockTime(ethers);
      let conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

      let tokenWin = await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, tokens(100));
      let tokenLose = await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, tokens(200));

      timeShift(time + ONE_HOUR);
      await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

      await poolBetting.connect(bettor).withdrawPayout([tokenWin]);
      await poolBetting.connect(bettor).withdrawPayout([tokenLose]);

      time = await getBlockTime(ethers);
      conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

      tokenWin = await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, tokens(400));
      tokenLose = await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, tokens(800));

      await poolBetting.connect(oracle).cancelCondition(conditionId);

      await poolBetting.connect(bettor).withdrawPayout([tokenWin]);
      await poolBetting.connect(bettor).withdrawPayout([tokenLose]);

      await poolBetting.connect(owner).claimDaoReward();

      expect(await wxDAI.balanceOf(owner.address)).to.be.equal(
        balance.add(BigNumber.from(tokens(300)).mul(FEE).div(MULTIPLIER))
      );
    });
  });
  describe("Check restrictions", async function () {
    describe("Conditions", async function () {
      beforeEach(async function () {
        time = await getBlockTime(ethers);
      });
      it("Only condition creator can resolve it", async () => {
        await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        await expect(poolBetting.connect(addr1).cancelCondition(conditionId)).to.be.revertedWith("OnlyOracle()");
        await expect(poolBetting.connect(addr1).resolveCondition(conditionId, OUTCOMEWIN)).to.be.revertedWith(
          "OnlyOracle()"
        );
      });
      it("Should NOT create conditions with incorrect betting peiod", async () => {
        await expect(createCondition(poolBetting, oracle, IPFS,time + ONE_HOUR, time + ONE_HOUR)).to.be.revertedWith("IncorrectBettingPeriod()");
      });
      it("Should NOT create conditions that will begin soon", async () => {
        await expect(createCondition(poolBetting, oracle, IPFS, time, time + 1)).to.be.revertedWith("ConditionExpired()");
      });
      it("Should NOT interact with nonexistent condition", async () => {
        const condIdNotExists = 2000000;
        await expect(makeBet(poolBetting, bettor, condIdNotExists, OUTCOMEWIN, BET)).to.be.revertedWith(
          `ConditionNotExists(${condIdNotExists})`
        );
        await expect(poolBetting.connect(oracle).resolveCondition(condIdNotExists, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotExists(${condIdNotExists})`
        );
        await expect(poolBetting.connect(oracle).cancelCondition(condIdNotExists)).to.be.revertedWith(
          `ConditionNotExists(${condIdNotExists})`
        );
      });
      it("Should NOT resolve condition before it starts", async () => {
        let conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        await expect(poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotStarted(${conditionId})`
        );
      });
      it("Should NOT resolve canceled condition", async () => {
        let conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        await expect(poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotStarted(${conditionId})`
        );
      });
      it("Should NOT resolve condition before it starts", async () => {
        let conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        await expect(poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionNotStarted(${conditionId})`
        );
      });
      it("Should NOT resolve condition with no bets on one of the outcomes", async () => {
        for (const outcome of [OUTCOMEWIN, OUTCOMELOSE]) {
          time = await getBlockTime(ethers);
          conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

          await makeBet(poolBetting, bettor, conditionId, outcome, BET);

          timeShift(time + ONE_HOUR);
          await expect(poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN)).to.be.revertedWith(
            `ConditionCanceled_(${conditionId++})`
          );
        }
      });
      it("Should NOT resolve condition with incorrect outcome", async () => {
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);

        await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await expect(poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEINCORRECT)).to.be.revertedWith(
          "WrongOutcome()"
        );
      });
      it("Should NOT resolve condition twice", async () => {
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        await expect(poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN)).to.be.revertedWith(
          `ConditionAlreadyResolved(${conditionId})`
        );
      });
      it("Should NOT cancel resolved condition", async () => {
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        await expect(poolBetting.connect(oracle).cancelCondition(conditionId)).to.be.revertedWith(
          `ConditionResolved_(${conditionId})`
        );
      });
    });
    describe("Bets", async function () {
      beforeEach(async function () {
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);
      });
      it("Should NOT bet out of betting period", async () => {
        const bettingStart = time + ONE_MINUTE;
        conditionId = await createCondition(poolBetting, oracle, IPFS, bettingStart, time + ONE_HOUR);

        await expect(makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET)).to.be.revertedWith(
          `BettingNotStarted(${bettingStart})`
        );

        timeShift(bettingStart);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await expect(makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET)).to.be.revertedWith(
          `BettingEnded()`
        );
      });
      it("Should NOT bet on condition that will begin soon if there are no bets on on of the outcomes", async () => {
        await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);

        timeShift(time + ONE_HOUR - 1);
        await expect(makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET)).to.be.revertedWith(
          `ConditionCanceled_(${conditionId})`
        );
      });
      it("Should NOT bet on canceled condition", async () => {
        await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).cancelCondition(conditionId);

        await expect(makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET)).to.be.revertedWith(
          `ConditionCanceled_(${conditionId})`
        );
      });
      it("Should NOT bet on incorrect outcome", async () => {
        await expect(makeBet(poolBetting, bettor, conditionId, OUTCOMEINCORRECT, BET)).to.be.revertedWith(
          "WrongOutcome()"
        );
      });
      it("Should NOT bet with no amount", async () => {
        await expect(makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, 0)).to.be.revertedWith(
          "AmountMustNotBeZero()"
        );
      });
      it("Should NOT bet with insufficient balance", async () => {
        const balance = await wxDAI.balanceOf(bettor.address);
        await expect(makeBet(poolBetting, addr1, conditionId, OUTCOMEWIN, balance.add(1))).to.be.revertedWith(
          "transferFrom failed"
        );
      });
    });
    describe("Payouts", async function () {
      let tokenWin, balance;
      beforeEach(async function () {
        time = await getBlockTime(ethers);
        conditionId = await createCondition(poolBetting, oracle, IPFS, time, time + ONE_HOUR);
      });
      it("Should NOT reward in case of lose", async () => {
        tokenWin = await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);
        await makeBet(poolBetting, bettor2, conditionId, OUTCOMEWIN, BET);
        balance = await wxDAI.balanceOf(bettor.address);

        timeShift(time + ONE_HOUR);
        poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        await poolBetting.connect(bettor).withdrawPayout([tokenWin]);
        expect(await wxDAI.balanceOf(bettor.address)).to.be.equal(balance);
      });
      it("Should NOT reward before condition ends", async () => {
        tokenWin = await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await expect(poolBetting.connect(bettor).withdrawPayout([tokenWin])).to.be.revertedWith(
          `ConditionStillOn(${conditionId})`
        );
      });
      it("Should NOT reward with zero bet token balance", async () => {
        tokenWin = await makeBet(poolBetting, bettor, conditionId, OUTCOMEWIN, BET);
        await makeBet(poolBetting, bettor, conditionId, OUTCOMELOSE, BET);

        timeShift(time + ONE_HOUR);
        await poolBetting.connect(oracle).resolveCondition(conditionId, OUTCOMEWIN);

        await expect(poolBetting.connect(bettor2).withdrawPayout([tokenWin])).to.be.revertedWith(
          `ZeroBalance(${tokenWin})`
        );
      });
    });
  });
});
