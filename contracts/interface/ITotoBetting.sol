// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

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
    event ConditionResolved(
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
}
