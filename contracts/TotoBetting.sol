// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

contract TotoBetting is OwnableUpgradeable {
    enum conditionState {
        CREATED,
        RESOLVED,
        CANCELED
    }

    struct Bet {
        uint256 conditionID;
        uint128 amount;
        uint64 outcome;
        uint64 createdAt;
        address bettor;
        bool payed;
    }

    struct Condition {
        uint128[2] totalNetBets;
        uint64[2] outcomes;
        uint128 scopeID;
        uint64 outcomeWin;
        uint64 timestamp;
        bytes32 ipfsHash;
        conditionState state;
    }

    address public token;
    uint128 public DAOFee;
    uint128 public DAOReward;

    uint64 public expireTimer;

    uint128 public decimals;

    mapping(address => bool) public oracles;
    mapping(address => mapping(uint256 => uint256)) public oracleConditionIDs; // oracle -> oracleConditionID -> conditionID

    mapping(uint256 => Condition) public conditions;
    uint256 public lastConditionID;

    mapping(uint256 => Bet) public bets; // tokenID -> BET
    uint256 public lastBetID;

    event OracleAdded(address indexed newOracle);
    event OracleRenounced(address indexed oracle);

    event ConditionCreated(
        uint256 indexed oracleCondID,
        uint256 indexed conditionID,
        uint64 timestamp
    );
    event ConditionResolved(
        uint256 indexed oracleCondID,
        uint256 indexed conditionID,
        uint64 outcomeWin
    );

    event NewBet(
        address indexed owner,
        uint256 indexed betID,
        uint256 indexed conditionID,
        uint64 outcomeId,
        uint128 amount
    );
    event BetterWin(address indexed better, uint128 amount);

    modifier onlyOracle() {
        require(oracles[msg.sender], "Permission denied: Oracle only");
        _;
    }

    modifier betAllowed(uint256 conditionID_) {
        require(
            !conditionIsCanceled(conditionID_) &&
                block.timestamp < conditions[conditionID_].timestamp,
            "Bet is not allowed"
        );
        _;
    }

    function initialize(
        address token_,
        address oracle_,
        uint128 fee_
    ) public virtual initializer {
        require(token_ != address(0), "Wrong token");

        __Ownable_init();
        oracles[oracle_] = true;
        DAOFee = fee_;
        expireTimer = 600;
        decimals = 10**9;
    }

    function setOracle(address oracle_) external onlyOwner {
        oracles[oracle_] = true;
        emit OracleAdded(oracle_);
    }

    function renounceOracle(address oracle_) external onlyOwner {
        oracles[oracle_] = false;
        emit OracleRenounced(oracle_);
    }

    function createCondition(
        uint256 oracleCondID_,
        uint64[2] memory outcomes_,
        uint128 scopeID_,
        uint64 timestamp_,
        bytes32 ipfsHash_
    ) external onlyOracle {
        require(timestamp_ > 0, "Timestamp can not be zero");
        require(
            timestamp_ + expireTimer < block.timestamp,
            "Condition is expired"
        );
        require(
            oracleConditionIDs[msg.sender][oracleCondID_] == 0,
            "Condition already exists"
        );

        lastConditionID++;
        oracleConditionIDs[msg.sender][oracleCondID_] = lastConditionID;

        Condition storage newCondition = conditions[lastConditionID];
        newCondition.outcomes = outcomes_;
        newCondition.scopeID = scopeID_;
        newCondition.timestamp = timestamp_;
        newCondition.ipfsHash = ipfsHash_;
        newCondition.state = conditionState.CREATED;

        emit ConditionCreated(oracleCondID_, lastConditionID, timestamp_);
    }

    function resolveCondition(uint256 oracleCondID_, uint64 outcomeWin_)
        external
        onlyOracle
    {
        uint256 conditionID = oracleConditionIDs[msg.sender][oracleCondID_];

        require(!conditionIsCanceled(conditionID), "Condition is canceled");
        require(
            outcomeIsCorrect(conditionID, outcomeWin_),
            "Incorrect outcome"
        );

        Condition storage condition = conditions[conditionID];

        require(condition.timestamp > 0, "Condition does not exist");
        require(
            block.timestamp >= condition.timestamp,
            "Condition has not started yet"
        );
        require(
            condition.state == conditionState.CREATED,
            "Condition already set"
        );
        uint128[2] memory fees = [
            (condition.totalNetBets[0] * DAOFee) / decimals,
            (condition.totalNetBets[1] * DAOFee) / decimals
        ];
        condition.totalNetBets[0] -= fees[0];
        condition.totalNetBets[1] -= fees[1];
        DAOReward += fees[0] + fees[1];

        condition.state = conditionState.RESOLVED;

        emit ConditionResolved(oracleCondID_, conditionID, outcomeWin_);
    }

    function conditionIsCanceled(uint256 conditionID_) internal returns (bool) {
        if (conditions[conditionID_].state == conditionState.CANCELED) {
            return true;
        }
        Condition storage condition = conditions[conditionID_];
        if (
            (block.timestamp + expireTimer >= condition.timestamp) &&
            (condition.totalNetBets[0] == 0 || condition.totalNetBets[1] == 0)
        ) {
            condition.state = conditionState.CANCELED;
            return true;
        }
        return false;
    }

    function outcomeIsCorrect(uint256 conditionID_, uint256 outcomeWin_)
        internal
        view
        returns (bool)
    {
        if (
            outcomeWin_ == conditions[conditionID_].outcomes[0] ||
            outcomeWin_ == conditions[conditionID_].outcomes[1]
        ) return true;
        return false;
    }

    function makeBet(
        uint256 conditionID_,
        uint128 amount_,
        uint64 outcomeWin_
    ) external betAllowed(conditionID_) returns (uint256) {
        require(amount_ > 0, "Amount must not be zero");
        require(
            outcomeIsCorrect(conditionID_, outcomeWin_),
            "Incorrect outcome"
        );

        Condition storage condition = conditions[conditionID_];

        uint8 outcomeIndex = (outcomeWin_ == condition.outcomes[0] ? 0 : 1);

        lastBetID++;
        bets[lastBetID] = Bet({
            conditionID: conditionID_,
            amount: amount_,
            outcome: outcomeWin_,
            createdAt: uint64(block.timestamp),
            bettor: msg.sender,
            payed: false
        });

        condition.totalNetBets[outcomeIndex] += amount_;

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount_
        );

        emit NewBet(msg.sender, lastBetID, conditionID_, outcomeWin_, amount_);

        return lastBetID;
    }

    function withdrawPayout(uint256 betID_) external {
        Bet storage bet = bets[betID_];
        require(bet.amount > 0, "Bet does not exist");
        require(bet.bettor == msg.sender, "Only bet owner");
        require(bet.payed == false, "Bet is already payed");

        Condition memory condition = conditions[bet.conditionID];
        require(
            condition.state == conditionState.RESOLVED == true ||
                conditionIsCanceled(bet.conditionID),
            "Condition is still on"
        );
        uint128 payout;
        if (condition.state == conditionState.RESOLVED) {
            if (bet.outcome != condition.outcomeWin) {
                payout = 0;
            } else {
                uint8 outcomeWinIndex = (
                    condition.outcomeWin == condition.outcomes[0] ? 0 : 1
                );
                payout =
                    condition.totalNetBets[0] +
                    (condition.totalNetBets[1] * bet.amount) /
                    condition.totalNetBets[outcomeWinIndex];
            }
        } else {
            payout = bet.amount;
        }

        bet.payed = true;
        TransferHelper.safeTransferFrom(
            token,
            address(this),
            msg.sender,
            payout
        );

        emit BetterWin(msg.sender, payout);
    }

    function claimDAOReward() external {
        require(DAOReward > 0, "No DAO reward");

        uint128 reward = DAOReward;
        DAOReward = 0;
        TransferHelper.safeTransfer(token, owner(), reward);
    }
}
