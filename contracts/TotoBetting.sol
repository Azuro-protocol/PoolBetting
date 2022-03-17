// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "./interface/ITotoBet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

/// @title Azuro Totalizator main contract
contract TotoBetting is OwnableUpgradeable {
    enum conditionState {
        CREATED,
        RESOLVED,
        CANCELED
    }

    struct Condition {
        uint128[2] totalNetBets;
        uint64[2] outcomes;
        bytes32 ipfsHash;
        uint128 scopeID;
        uint64 outcomeWin;
        uint64 timestamp;
        conditionState state;
    }

    address public token;
    ITotoBet betToken;

    uint128 public DAOFee;
    uint128 public DAOReward;

    // The condition expires if during this time before it starts there were no bets on one of the outcomes
    uint64 public expireTimer;

    uint128 public decimals;

    mapping(address => bool) public oracles;
    mapping(address => mapping(uint256 => uint256)) public oracleConditionIDs; // oracle -> oracleConditionID -> conditionID

    mapping(uint256 => Condition) public conditions;
    uint256 public lastConditionID;

    event TotoBetChanged(address indexed newTotoBet);

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
        uint256 indexed conditionID,
        uint256 indexed tokenId,
        uint64 outcomeID,
        uint128 amount
    );
    event BetterWin(
        address indexed better,
        uint256 indexed tokenId,
        uint256 amount
    );

    /**
     * @dev requires the function to be called only by oracle
     */
    modifier onlyOracle() {
        require(oracles[msg.sender], "Oracle only");
        _;
    }

    /**
     * @dev requires the condition have such outcome
     * @param conditionID_ the match or game id
     * @param outcome_ outcome id
     */
    modifier outcomeIsCorrect(uint256 conditionID_, uint256 outcome_) {
        require(isOutcomeCorrect(conditionID_, outcome_), "Incorrect outcome");
        _;
    }

    /**
     * @dev requires the condition to allow new bets
     * @param conditionID_ the match or game id
     */
    modifier betAllowed(uint256 conditionID_) {
        require(
            !conditionIsCanceled(conditionID_) &&
                block.timestamp < conditions[conditionID_].timestamp,
            "Bet is not allowed"
        );
        _;
    }

    /**
     * @dev initialize TotoBetting contract
     * @param token_ address of the token used in bets and rewards
     * @param totoBet_ TotoBet contract address
     * @param oracle_ oracle address
     * @param fee_ bet fee in decimals 10^9
     */
    function initialize(
        address token_,
        address totoBet_,
        address oracle_,
        uint128 fee_
    ) public virtual initializer {
        require(token_ != address(0), "Wrong token");

        __Ownable_init();
        betToken = ITotoBet(totoBet_);
        oracles[oracle_] = true;
        DAOFee = fee_;
        expireTimer = 600;
        decimals = 10**9;
    }

    /**
     * @dev set new TotoBet contract
     * @param totoBet_ new TotoBet contract address
     */
    function changeTotoBet(address totoBet_) external onlyOwner {
        betToken = ITotoBet(totoBet_);
        emit TotoBetChanged(totoBet_);
    }

    /**
     * @dev add new oracle
     * @param oracle_ new oracle address
     */
    function addOracle(address oracle_) external onlyOwner {
        oracles[oracle_] = true;
        emit OracleAdded(oracle_);
    }

    /**
     * @dev renounce oracle
     * @param oracle_ address of oracle to renounce
     */
    function renounceOracle(address oracle_) external onlyOwner {
        oracles[oracle_] = false;
        emit OracleRenounced(oracle_);
    }

    /**
     * @dev create new condition by oracle
     * @param oracleConditionID_ the current match or game id in oracle's internal system
     * @param outcomes_ outcome ids for this condition [outcomeID 1, outcomeID 2]
     * @param scopeID_ id of the competition or event the condition belongs
     * @param timestamp_ time when match starts and bets not allowed
     * @param ipfsHash_ detailed info about math stored in IPFS
     */
    function createCondition(
        uint256 oracleConditionID_,
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
            oracleConditionIDs[msg.sender][oracleConditionID_] == 0,
            "Condition already exists"
        );

        lastConditionID++;
        oracleConditionIDs[msg.sender][oracleConditionID_] = lastConditionID;

        Condition storage newCondition = conditions[lastConditionID];
        newCondition.outcomes = outcomes_;
        newCondition.scopeID = scopeID_;
        newCondition.timestamp = timestamp_;
        newCondition.ipfsHash = ipfsHash_;
        newCondition.state = conditionState.CREATED;

        emit ConditionCreated(oracleConditionID_, lastConditionID, timestamp_);
    }

    /**
     * @dev resolve existing condition by oracle
     * @param oracleConditionID_ the match or game id in oracle's internal system
     * @param outcomeWin_ id of happened outcome
     */
    function resolveCondition(uint256 oracleConditionID_, uint64 outcomeWin_)
        external
        onlyOracle
    {
        uint256 conditionID = oracleConditionIDs[msg.sender][
            oracleConditionID_
        ];

        require(!conditionIsCanceled(conditionID), "Condition is canceled");
        require(
            isOutcomeCorrect(conditionID, outcomeWin_),
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

        emit ConditionResolved(oracleConditionID_, conditionID, outcomeWin_);
    }

    /**
     * @dev check if the condition have such outcome
     * @param conditionID_ the match or game id
     * @param outcome_ outcome id
     * @return true if the condition have such outcome id else false
     */
    function isOutcomeCorrect(uint256 conditionID_, uint256 outcome_)
        internal
        view
        returns (bool)
    {
        if (
            outcome_ == conditions[conditionID_].outcomes[0] ||
            outcome_ == conditions[conditionID_].outcomes[1]
        ) return true;
        return false;
    }

    /**
     * @dev cancel existing condition by oracle
     * @param oracleConditionID_ the current match or game id in oracle's internal system
     */
    function cancelCondition(uint256 oracleConditionID_) internal onlyOracle {
        Condition storage condition = conditions[
            oracleConditionIDs[msg.sender][oracleConditionID_]
        ];

        require(condition.timestamp > 0, "Condition does not exist");
        require(
            condition.state != conditionState.CANCELED,
            "Condition is already canceled"
        );

        condition.state = conditionState.CANCELED;
    }

    /**
     * @dev check if the condition is canceled
     * @param conditionID_ the match or game id
     * @return true if the condition is canceled else false
     */
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

    /**
     * @dev register new bet
     * @param conditionID_ the match or game id
     * @param outcomeWin_ predicted outcome id
     * @param amount_ bet amount in tokens
     */
    function makeBet(
        uint256 conditionID_,
        uint64 outcomeWin_,
        uint128 amount_
    )
        external
        betAllowed(conditionID_)
        outcomeIsCorrect(conditionID_, outcomeWin_)
    {
        require(amount_ > 0, "Amount must not be zero");

        Condition storage condition = conditions[conditionID_];

        uint8 outcomeIndex = (outcomeWin_ == condition.outcomes[0] ? 0 : 1);

        condition.totalNetBets[outcomeIndex] += amount_;

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount_
        );

        uint256 tokenID = betToken.mint(
            msg.sender,
            lastConditionID,
            outcomeIndex,
            amount_
        );

        emit NewBet(msg.sender, conditionID_, tokenID, outcomeWin_, amount_);
    }

    /**
     * @dev withdraw bettor prize
     * @param conditionID_ the match or game id
     * @param outcomeWin_ the outcome id on which the bet was placed
     */
    function withdrawPayout(uint256 conditionID_, uint64 outcomeWin_)
        external
        outcomeIsCorrect(conditionID_, outcomeWin_)
    {
        Condition memory condition = conditions[conditionID_];

        require(
            condition.state == conditionState.RESOLVED == true ||
                conditionIsCanceled(conditionID_),
            "Condition is still on"
        );

        uint8 outcomeWinIndex = (outcomeWin_ == condition.outcomes[0] ? 0 : 1);
        uint256 tokenID = betToken.getTokenID(
            address(this),
            conditionID_,
            outcomeWinIndex
        );
        uint256 balance = betToken.balanceOf(msg.sender, tokenID);

        require(
            balance > 0,
            "You have no bet tokens for such condition outcome"
        );

        uint256 payout;
        if (condition.state == conditionState.RESOLVED) {
            if (tokenID % 2 == outcomeWinIndex) {
                payout = 0;
            } else {
                payout =
                    ((condition.totalNetBets[0] + condition.totalNetBets[1]) *
                        balance) /
                    condition.totalNetBets[outcomeWinIndex];
            }
        } else {
            payout = balance;
        }

        betToken.burn(msg.sender, tokenID, outcomeWinIndex, balance);
        TransferHelper.safeTransferFrom(
            token,
            address(this),
            msg.sender,
            payout
        );

        emit BetterWin(msg.sender, tokenID, payout);
    }

    /**
     * @dev reward contract owner with total amount of charged fees
     */
    function claimDAOReward() external {
        require(DAOReward > 0, "No DAO reward");

        uint128 reward = DAOReward;
        DAOReward = 0;
        TransferHelper.safeTransfer(token, owner(), reward);
    }
}
