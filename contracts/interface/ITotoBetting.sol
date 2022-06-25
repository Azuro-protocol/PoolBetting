// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

interface ITotoBetting {
    enum ConditionState {
        CREATED,
        RESOLVED,
        CANCELED
    }

    struct Condition {
        uint128[2] totalNetBets;
        uint64[2] outcomes;
        uint128 scopeId;
        bytes32 ipfsHash;
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

    // Some errors have same names as events or modifiers so used "E" prefix
    error EOnlyOracle();

    error EWrongToken();
    error EWrongFee();
    error EWrongOutcome();
    error ESameOutcomes();
    error EConditionExpired();

    error EConditionNotExists(uint256 conditionId);
    error EConditionAlreadyCreated(uint256 conditionId);
    error EConditionNotYetStarted(uint256 conditionId);
    error EConditionStillOn(uint256 conditionId);
    error EConditionStarted(uint256 conditionId);
    error EConditionResolved(uint256 conditionId);
    error EConditionAlreadyResolved(uint256 conditionId);
    error EConditionCanceled(uint256 conditionId);
    error EConditionAlreadyCanceled(uint256 conditionId);

    error EAmountMustNotBeZero();
    error EZeroBalance(uint256 tokenId);
    error ENoDAOReward();
}
