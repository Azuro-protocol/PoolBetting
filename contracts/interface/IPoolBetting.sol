// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

interface IPoolBetting {
    enum ConditionState {
        CREATED,
        RESOLVED,
        CANCELED
    }

    struct Condition {
        bytes32 ipfsHash;
        uint128[2] totalNetBets;
        uint64[2] outcomes;
        uint64 outcomeWon;
        uint64 timestamp;
        ConditionState state;
    }

    event OracleAdded(address indexed newOracle);
    event OracleRenounced(address indexed oracle);

    event ConditionCreated(
        uint256 indexed oracleConditionId,
        uint256 indexed conditionId,
        uint64 timestamp
    );
    event ConditionResolved(
        uint256 indexed oracleConditionId,
        uint256 indexed conditionId,
        uint64 outcomeWin
    );
    event ConditionCanceled(
        uint256 indexed oracleConditionId,
        uint256 indexed conditionId
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
    error SameOutcomes();
    error ConditionExpired();

    error ConditionNotExists(uint256 conditionId);
    error ConditionAlreadyCreated(uint256 conditionId);
    error ConditionNotStarted(uint256 conditionId);
    error ConditionStillOn(uint256 conditionId);
    error ConditionStarted(uint256 conditionId);
    error ConditionResolved_(uint256 conditionId);
    error ConditionAlreadyResolved(uint256 conditionId);
    error ConditionCanceled_(uint256 conditionId);
    error ConditionAlreadyCanceled(uint256 conditionId);

    error AmountMustNotBeZero();
    error ZeroBalance(uint256 tokenId);
    error NoDAOReward();
}
