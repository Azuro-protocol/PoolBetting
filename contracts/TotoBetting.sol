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

    uint128 public multiplier;

    mapping(address => bool) public oracles;
    mapping(address => mapping(uint256 => uint256)) public oracleConditionIDs; // oracle -> oracleConditionID -> conditionID

    mapping(uint256 => Condition) public conditions;
    uint256 public lastConditionID; // starts with 1

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
        multiplier = 10**9;

        require(fee_ < multiplier, "Fee share should be less than 100%");

        token = token_;
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
        uint128 scopeID_,
        uint64[2] calldata outcomes_,
        uint64 timestamp_,
        bytes32 ipfsHash_
    ) external onlyOracle {
        require(
            oracleConditionIDs[msg.sender][oracleConditionID_] == 0,
            "Condition already exists"
        );
        require(outcomes_[0] != outcomes_[1], "Incorrect outcomes");
        require(
            timestamp_ > block.timestamp + expireTimer,
            "Condition is expired"
        );

        oracleConditionIDs[msg.sender][oracleConditionID_] = ++lastConditionID;

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

        Condition storage condition = getCondition(conditionID);

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

        DAOReward +=
            ((condition.totalNetBets[0] + condition.totalNetBets[1]) * DAOFee) /
            multiplier;

        condition.outcomeWon = outcomeWon_;
        condition.state = conditionState.RESOLVED;

        emit ConditionResolved(oracleConditionID_, conditionID, outcomeWon_);
    }

    /**
     * @notice Get condition with id `conditionID_`
     * @param  conditionID_ the match or game id
     * @return the match or game struct
     */
    function getCondition(uint256 conditionID_)
        internal
        view
        returns (Condition storage)
    {
        Condition storage condition = conditions[conditionID_];

        require(condition.timestamp > 0, "Condition does not exist");

        return condition;
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
     * @notice  Oracle: Indicate the condition `oracleConditionID_` as canceled
     * @param   oracleConditionID_ the current match or game id in oracle's internal system
     */
    function cancelCondition(uint256 oracleConditionID_) external onlyOracle {
        Condition storage condition = getCondition(
            oracleConditionIDs[msg.sender][oracleConditionID_]
        );

        require(
            condition.state != conditionState.RESOLVED,
            "Condition is resolved"
        );
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
        Condition storage condition = getCondition(conditionID_);

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
     * @dev    Minted tokenID = 2 * `conditionID_` + index of outcome `outcome_` in condition struct
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

        Condition storage condition = getCondition(conditionID_);

        require(
            !conditionIsCanceled(conditionID_) &&
                block.timestamp < condition.timestamp,
            "Bet is not allowed"
        );
        outcomeIsCorrect(condition, outcome_);

        uint256 tokenID = getTokenID(conditionID_, outcome_);

        condition.totalNetBets[(tokenID + 1) % 2] += amount_;

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
     * @notice Get token id of bet on outcome `outcome_` in condition `conditionID_`
     * @param  conditionID_ the match or game id
     * @param  outcome_ id of predicted outcome
     * @return bet token id
     */
    function getTokenID(uint256 conditionID_, uint64 outcome_)
        public
        view
        returns (uint256)
    {
        Condition memory condition = getCondition(conditionID_);

        outcomeIsCorrect(condition, outcome_);

        return conditionID_ * 2 - (outcome_ == condition.outcomes[0] ? 1 : 0);
    }

    /**
     * @notice Withdraw payout based on bets in finished or cancelled conditions
     * @param  tokensIDs_ array of bet tokens ids withdraw payout to
     */
    function withdrawPayout(uint256[] calldata tokensIDs_) external {
        uint256 totalPayout;
        uint256 refunds;
        for (uint256 i = 0; i < tokensIDs_.length; i++) {
            uint256 tokenID = tokensIDs_[i];
            uint256 conditionID = (tokenID + 1) / 2;
            Condition memory condition = getCondition(conditionID);

            require(
                condition.state == conditionState.RESOLVED ||
                    conditionIsCanceled(conditionID),
                "Condition is still on"
            );

            uint256 balance = super.balanceOf(msg.sender, tokenID);

            require(balance > 0, "You have no bet tokens");

            super._burn(msg.sender, tokenID, balance);

            uint256 outcomeWinIndex = (tokenID + 1) % 2; // uint256 used to reduce gas consumption
            if (condition.state == conditionState.RESOLVED) {
                if (
                    condition.outcomes[outcomeWinIndex] == condition.outcomeWon
                ) {
                    totalPayout +=
                        ((condition.totalNetBets[0] +
                            condition.totalNetBets[1]) * balance) /
                        condition.totalNetBets[outcomeWinIndex];
                }
            } else {
                refunds += balance;
            }
        }
        totalPayout =
            (totalPayout * (multiplier - DAOFee)) /
            multiplier +
            refunds;

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
