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

    event OracleAdded(address indexed newOracle);
    event OracleRenounced(address indexed oracle);

    event ConditionCreated(
        uint256 indexed oracleConditionID,
        uint256 indexed conditionID,
        uint64 timestamp
    );
    event ConditionResolved(
        uint256 indexed oracleConditionID,
        uint256 indexed conditionID,
        uint64 outcomeWin
    );
    event ConditionCanceled(uint256 indexed conditionID);

    event NewBet(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed conditionID,
        uint64 outcome,
        uint128 amount
    );

    event BettorWin(
        address indexed bettor,
        uint256[] indexed tokensIDs,
        uint256 amount
    );
    // Some errors have same names as events or modifiers so used "E" prefix
    error EOnlyOracle();

    error EWrongToken();
    error EWrongFee();
    error EWrongOutcome();
    error ESameOutcomes();
    error EConditionExpired();

    error EConditionNotExists(uint256 conditionID);
    error EConditionAlreadyCreated(uint256 conditionID);
    error EConditionNotYetStarted(uint256 conditionID);
    error EConditionStillOn(uint256 conditionID);
    error EConditionStarted(uint256 conditionID);
    error EConditionResolved(uint256 conditionID);
    error EConditionAlreadyResolved(uint256 conditionID);
    error EConditionCanceled(uint256 conditionID);
    error EConditionAlreadyCanceled(uint256 conditionID);

    error EAmountMustNotBeZero();
    error EZeroBalance(uint256 tokenID);
}
