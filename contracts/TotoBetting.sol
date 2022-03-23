// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

import "./interface/ITotoBetting.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

/// @title Azuro Totalizator main contract
contract TotoBetting is ERC1155Upgradeable, OwnableUpgradeable, ITotoBetting {
    address public token;

    uint128 public DAOFee;
    uint128 public DAOReward;

    // The condition expires if during this time before it starts there were no bets on one of the outcomes
    uint64 public expireTimer;

    uint128 public decimals;

    mapping(address => bool) public oracles;
    mapping(address => mapping(uint256 => uint256)) public oracleConditionIDs; // oracle -> oracleConditionID -> conditionID

    mapping(uint256 => Condition) public conditions;
    uint256 public lastConditionID;

    /**
     * @notice Requires the function to be called only by oracle
     */
    modifier onlyOracle() {
        require(oracles[msg.sender], "Oracle only");
        _;
    }

    /**
     * @param  token_ address of the token used in bets and rewards
     * @param  oracle_ oracle address
     * @param  fee_ bet fee in decimals 10^9
     */
    function initialize(
        address token_,
        address oracle_,
        uint128 fee_
    ) public virtual initializer {
        require(token_ != address(0), "Wrong token");

        __Ownable_init();
        __ERC1155_init("Toto Betting");
        decimals = 10**9;

        require(fee_ < decimals, "Fee share should be less than 100%");

        oracles[oracle_] = true;
        expireTimer = 600;
        DAOFee = fee_;
    }

    /**
     * @notice Indicate address `oracle_` as oracle
     * @param  oracle_ new oracle address
     */
    function addOracle(address oracle_) external onlyOwner {
        oracles[oracle_] = true;
        emit OracleAdded(oracle_);
    }

    /**
     * @notice Do not consider address `oracle_` a oracle anymore
     * @param  oracle_ address of oracle to renounce
     */
    function renounceOracle(address oracle_) external onlyOwner {
        oracles[oracle_] = false;
        emit OracleRenounced(oracle_);
    }

    /**
     * @notice Oracle: Provide information about current condition
     * @param  oracleConditionID_ the current match or game id in oracle's internal system
     * @param  outcomes_ outcome ids for this condition [outcome 1, outcome 2]
     * @param  scopeID_ id of the competition or event the condition belongs
     * @param  timestamp_ time when match starts and bets not allowed
     * @param  ipfsHash_ detailed info about match stored in IPFS
     */
    function createCondition(
        uint256 oracleConditionID_,
        uint64[2] calldata outcomes_,
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
     * @notice (Oracle) Indicate outcome `outcomeWon_` as happened in oracle's condition `oracleConditionID_`
     * @param  oracleConditionID_ the match or game id in oracle's internal system
     * @param  outcomeWon_ id of happened outcome
     */
    function resolveCondition(uint256 oracleConditionID_, uint64 outcomeWon_)
        external
        onlyOracle
    {
        uint256 conditionID = oracleConditionIDs[msg.sender][
            oracleConditionID_
        ];
        Condition storage condition = conditions[conditionID];

        require(!conditionIsCanceled(conditionID), "Condition is canceled");
        require(
            condition.state == conditionState.CREATED,
            "Condition already set"
        );
        require(
            block.timestamp >= condition.timestamp,
            "Condition has not started yet"
        );
        outcomeIsCorrect(condition, outcomeWon_);

        uint128[2] memory fees = [
            (condition.totalNetBets[0] * DAOFee) / decimals,
            (condition.totalNetBets[1] * DAOFee) / decimals
        ];
        condition.totalNetBets[0] -= fees[0];
        condition.totalNetBets[1] -= fees[1];
        DAOReward += fees[0] + fees[1];

        condition.state = conditionState.RESOLVED;

        emit ConditionResolved(oracleConditionID_, conditionID, outcomeWon_);
    }

    /**
     * @notice Require the condition have outcome `outcome_` as possible
     * @param  condition_ the match or game struct
     * @param  outcome_ outcome id
     */
    function outcomeIsCorrect(Condition memory condition_, uint256 outcome_)
        internal
        pure
    {
        require(
            outcome_ == condition_.outcomes[0] ||
                outcome_ == condition_.outcomes[1],
            "Incorrect outcome"
        );
    }

    /**
     * @notice Require the condition is existing
     * @param  condition_ the match or game struct
     */
    function conditionExists(Condition memory condition_) internal pure {
        require(condition_.timestamp > 0, "Condition does not exist");
    }

    /**
     * @notice  Oracle: Indicate the condition `oracleConditionID_` as canceled
     * @param   oracleConditionID_ the current match or game id in oracle's internal system
     */
    function cancelCondition(uint256 oracleConditionID_) internal onlyOracle {
        Condition storage condition = conditions[
            oracleConditionIDs[msg.sender][oracleConditionID_]
        ];

        conditionExists(condition);
        require(
            condition.state != conditionState.CANCELED,
            "Condition is already canceled"
        );

        condition.state = conditionState.CANCELED;
    }

    /**
     * @notice Check if the condition `conditionID_` is canceled
     * @dev    Previously cancel the condition if during `expireTime` sec before it starts there are no bets on one of the outcomes
     * @param  conditionID_ the match or game id
     * @return true if the condition is canceled else false
     */
    function conditionIsCanceled(uint256 conditionID_) internal returns (bool) {
        Condition storage condition = conditions[conditionID_];

        conditionExists(condition);

        if (condition.state == conditionState.CANCELED) {
            return true;
        }
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
     * @notice Bet `amount_` tokens that in the condition `conditionID_` will happen outcome with id `outcome_`
     * @param  conditionID_ the match or game id
     * @param  outcome_ id of predicted outcome
     * @param  amount_ bet amount in tokens
     */
    function makeBet(
        uint256 conditionID_,
        uint64 outcome_,
        uint128 amount_
    ) external {
        require(amount_ > 0, "Bet amount must not be zero");

        Condition storage condition = conditions[conditionID_];

        require(
            !conditionIsCanceled(conditionID_) &&
                block.timestamp < condition.timestamp,
            "Bet is not allowed"
        );
        outcomeIsCorrect(condition, outcome_);

        uint8 outcomeIndex = (outcome_ == condition.outcomes[0] ? 0 : 1);

        condition.totalNetBets[outcomeIndex] += amount_;

        uint256 tokenID = conditionID_ * 2 + outcomeIndex;

        super._mint(msg.sender, tokenID, amount_, "");

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount_
        );

        emit NewBet(msg.sender, tokenID, conditionID_, outcome_, amount_);
    }

    /**
     * @notice Withdraw payout based on bets in finished or cancelled conditions
     * @param  tokensIDs_ array of bet tokens ids withdraw payout to
     */
    function withdrawPayout(uint256[] calldata tokensIDs_) external {
        uint256 totalPayout;

        for (uint256 i = 0; i < tokensIDs_.length; i++) {
            uint256 tokenID = tokensIDs_[i];
            uint256 conditionID = tokenID / 2;
            Condition memory condition = conditions[conditionID];

            require(
                condition.state == conditionState.RESOLVED ||
                    conditionIsCanceled(conditionID),
                "Condition is still on"
            );

            uint256 balance = super.balanceOf(msg.sender, tokenID);

            require(balance > 0, "You have no bet tokens");

            super._burn(msg.sender, tokenID, balance);
            
            uint256 outcomeWinIndex = tokenID % 2; // uint256 used to reduce gas consumption
            if (condition.state == conditionState.RESOLVED) {
                if (condition.outcomes[outcomeWinIndex] == condition.outcomeWon) {
                    totalPayout +=
                        ((condition.totalNetBets[0] +
                            condition.totalNetBets[1]) * balance) /
                        condition.totalNetBets[outcomeWinIndex];
                } else {
                    totalPayout += balance;
                }
            }
        }

        TransferHelper.safeTransfer(token, msg.sender, totalPayout);

        emit BetterWin(msg.sender, tokensIDs_, totalPayout);
    }

    /**
     * @notice Reward contract owner with total amount of charged fees
     */
    function claimDAOReward() external {
        require(DAOReward > 0, "No DAO reward");

        uint128 reward = DAOReward;
        DAOReward = 0;
        TransferHelper.safeTransfer(token, owner(), reward);
    }
}
