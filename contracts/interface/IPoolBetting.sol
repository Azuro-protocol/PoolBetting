// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

interface IPoolBetting {
    enum ConditionState {
        CREATED,
        RESOLVED,
        CANCELED
    }

    struct Condition {
        address oracle;
        bytes32 ipfsHash;
        uint128[2] totalNetBets;
        uint64 bettingStartsAt;
        uint64 bettingEndsAt;
        uint8 outcomeWin;
        ConditionState state;
    }

    event BettorWin(address indexed bettor, uint256[] tokenId, uint128 amount);

    event ConditionCreated(
        address indexed oracle,
        uint256 indexed conditionId,
        uint64 bettingStartsAt,
        uint64 bettingEndsAt
    );
    event ConditionCanceled(uint256 indexed conditionId);
    event ConditionResolved(uint256 indexed conditionId, uint64 outcomeWin);
    event ConditionShifted(
        uint256 indexed conditionId,
        uint64 bettingStartsAt,
        uint64 bettingEndsAt
    );

    event NewBet(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed conditionId,
        uint64 outcome,
        uint128 amount
    );

    error OnlyOracle();

    error WrongFee();
    error WrongToken();
    error WrongOutcome();

    error ConditionExpired();
    error ConditionExpiredAfterShift();
    error ConditionNotExists();
    error ConditionNotStarted(uint64 bettingEndsAt);
    error ConditionStillOn(uint256 conditionId);
    error ConditionStarted();
    error ConditionResolved_();
    error ConditionAlreadyResolved();
    error ConditionCanceled_();
    error ConditionAlreadyCanceled();

    error AmountMustNotBeZero();
    error BettingNotStarted(uint64 bettingEndsAt);
    error BettingEnded(uint64 endsAt);
    error NoDaoReward();
    error ZeroBalance(uint256 tokenId);
}
