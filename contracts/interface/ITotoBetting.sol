// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

interface ITotoBetting {
    enum conditionState {
        CREATED,
        RESOLVED,
        CANCELED
    }

    struct Condition {
        uint128[2] totalNetBets;
        uint64[2] outcomes;
        uint128 scopeID;
        bytes32 ipfsHash;
        uint64 outcomeWon;
        uint64 timestamp;
        conditionState state;
    }

    event TotoBetChanged(address indexed newTotoBet);

    event OracleAdded(address indexed newOracle);
    event OracleRenounced(address indexed oracle);

    event ConditionCreated(
        uint256 indexed oracleConditionID,
        uint256 indexed conditionID,
        uint64 timestamp
    );
    event ConditionSet(
        uint256 indexed oracleConditionID,
        uint256 indexed conditionID,
        uint64 outcomeWin
    );

    event NewBet(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed conditionID,
        uint64 outcome,
        uint128 amount
    );

    event BetterWin(
        address indexed better,
        uint256[] indexed tokensIDs,
        uint256 amount
    );

    error OnlyOracle();

    error WrongToken();
    error WrongFee();
    error WrongOutcome();
    error SameOutcomes();
    error ConditionExpired();

    error ConditionNotExists(uint256 conditionID);
    error ConditionAlreadyCreated(uint256 conditionID);
    error ConditionNotYetStarted(uint256 conditionID);
    error ConditionStillOn(uint256 conditionID);
    error ConditionStarted(uint256 conditionID);
    error ConditionResolved(uint256 conditionID);
    error ConditionAlreadyResolved(uint256 conditionID);
    error ConditionCanceled(uint256 conditionID);
    error ConditionAlreadyCanceled(uint256 conditionID);

    error AmountMustNotBeZero();
    error ZeroBalance(uint256 tokenID);
}
