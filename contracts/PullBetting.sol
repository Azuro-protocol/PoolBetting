// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "./interface/IPullBetting.sol";
import "./interface/IWNative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

/// @title Azuro Totalizator
contract PullBetting is OwnableUpgradeable, ERC1155Upgradeable, IPullBetting {
    address public token;

    uint128 public daoFee;
    uint128 public DAOReward;

    /**
     * @notice The condition expires if during this time before it starts there were no bets on one of the outcomes.
     */
    uint64 public expireTimer;

    uint48 public multiplier;

    mapping(address => bool) public oracles;
    mapping(address => mapping(uint256 => uint256)) public oracleCondIds; // oracle -> oracleConditionId -> conditionId

    mapping(uint256 => Condition) public conditions;
    uint256 public lastConditionId; // starts with 1

    /**
     * @notice Requires the function to be called only by oracle.
     */
    modifier onlyOracle() {
        if (!oracles[msg.sender]) revert OnlyOracle();
        _;
    }

    receive() external payable {
        assert(msg.sender == token); // only accept native tokens via fallback from the WETH contract
    }

    /**
     * @param  token_ address of the token used in bets and rewards
     * @param  oracle oracle address
     * @param  fee bet fee in decimals 10^9
     */
    function initialize(
        address token_,
        address oracle,
        uint128 fee
    ) external virtual initializer {
        if (token_ == address(0)) revert WrongToken();

        __Ownable_init();
        __ERC1155_init("Pull Betting");
        multiplier = 10**12;

        if (fee >= multiplier) revert WrongFee();
        token = token_;
        oracles[oracle] = true;
        expireTimer = 600;
        daoFee = fee;
    }

    /**
     * @notice Indicate address `oracle` as oracle.
     * @param  oracle new oracle address
     */
    function addOracle(address oracle) external onlyOwner {
        oracles[oracle] = true;
        emit OracleAdded(oracle);
    }

    /**
     * @notice Do not consider address `oracle` a oracle anymore.
     * @param  oracle address of oracle to renounce
     */
    function renounceOracle(address oracle) external onlyOwner {
        oracles[oracle] = false;
        emit OracleRenounced(oracle);
    }

    /**
     * @notice Oracle: Provide information about current condition.
     * @param  oracleCondId the current match or game id in oracle's internal system
     * @param  outcomes outcome ids for this condition [outcome 1, outcome 2]
     * @param  timestamp time when match starts and bets not allowed
     * @param  ipfsHash detailed info about match stored in IPFS
     */
    function createCondition(
        uint256 oracleCondId,
        uint64[2] calldata outcomes,
        uint64 timestamp,
        bytes32 ipfsHash
    ) external onlyOracle {
        uint256 conditionId = oracleCondIds[msg.sender][oracleCondId];
        if (conditionId != 0) revert ConditionAlreadyCreated(conditionId);
        if (outcomes[0] == outcomes[1]) revert SameOutcomes();
        if (timestamp <= block.timestamp + expireTimer)
            revert ConditionExpired();

        oracleCondIds[msg.sender][oracleCondId] = ++lastConditionId;

        Condition storage newCondition = conditions[lastConditionId];
        newCondition.outcomes = outcomes;
        newCondition.timestamp = timestamp;
        newCondition.ipfsHash = ipfsHash;

        emit ConditionCreated(oracleCondId, lastConditionId, timestamp);
    }

    /**
     * @notice Oracle: Indicate outcome `outcomeWon` as happened in oracle's condition `oracleCondId`.
     * @param  oracleCondId the match or game id in oracle's internal system
     * @param  outcomeWon id of happened outcome
     */
    function resolveCondition(uint256 oracleCondId, uint64 outcomeWon)
        external
        onlyOracle
    {
        uint256 conditionId = oracleCondIds[msg.sender][oracleCondId];

        Condition storage condition = getCondition(conditionId);

        if (conditionIsCanceled(conditionId))
            revert ConditionCanceled_(conditionId);
        if (condition.state != ConditionState.CREATED)
            revert ConditionAlreadyResolved(conditionId);
        if (block.timestamp < condition.timestamp)
            revert ConditionNotStarted(conditionId);

        outcomeIsCorrect(condition, outcomeWon);

        DAOReward +=
            ((condition.totalNetBets[0] + condition.totalNetBets[1]) * daoFee) /
            multiplier;

        condition.outcomeWon = outcomeWon;
        condition.state = ConditionState.RESOLVED;

        emit ConditionResolved(oracleCondId, conditionId, outcomeWon);
    }

    /**
     * @notice Get condition with id `conditionId`.
     * @param  conditionId the match or game id
     * @return the match or game struct
     */
    function getCondition(uint256 conditionId)
        internal
        view
        returns (Condition storage)
    {
        Condition storage condition = conditions[conditionId];

        if (condition.timestamp == 0) revert ConditionNotExists(conditionId);

        return condition;
    }

    /**
     * @notice Require the condition `conditionId` have outcome `outcome` as possible.
     * @param  condition the match or game struct
     * @param  outcome outcome id
     */
    function outcomeIsCorrect(Condition memory condition, uint64 outcome)
        internal
        pure
    {
        if (
            outcome != condition.outcomes[0] && outcome != condition.outcomes[1]
        ) revert WrongOutcome();
    }

    /**
     * @notice  Oracle: Indicate the condition `oracleCondId` as canceled.
     * @param   oracleCondId the current match or game id in oracle's internal system
     */
    function cancelCondition(uint256 oracleCondId) external onlyOracle {
        uint256 conditionId = oracleCondIds[msg.sender][oracleCondId];
        Condition storage condition = getCondition(conditionId);

        if (condition.state == ConditionState.RESOLVED)
            revert ConditionResolved_(conditionId);
        if (condition.state == ConditionState.CANCELED)
            revert ConditionAlreadyCanceled(conditionId);

        condition.state = ConditionState.CANCELED;

        emit ConditionCanceled(oracleCondId, conditionId);
    }

    /**
     * @notice Check if the condition `conditionId` is canceled.
     * @dev    Previously cancel the condition if during `expireTime` sec before it starts there are no bets on one of the outcomes.
     * @param  conditionId the match or game id
     * @return true if the condition is canceled else false
     */
    function conditionIsCanceled(uint256 conditionId) internal returns (bool) {
        Condition storage condition = getCondition(conditionId);

        if (condition.state == ConditionState.CANCELED) {
            return true;
        }
        if (
            (block.timestamp + expireTimer >= condition.timestamp) &&
            (condition.totalNetBets[0] == 0 || condition.totalNetBets[1] == 0)
        ) {
            condition.state = ConditionState.CANCELED;

            emit ConditionCanceled(0, conditionId);

            return true;
        }
        return false;
    }

    /**
     * @notice Bet `amount` tokens that in the condition `conditionId` will happen outcome with id `outcome`.
     * @dev    See {_bet}.
     */
    function bet(
        uint256 conditionId,
        uint64 outcome,
        uint128 amount
    ) external {
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );
        _bet(conditionId, outcome, amount);
    }

    /**
     * @notice Bet transferred native tokens that in the condition `conditionId` will happen outcome with id `outcome`.
     * @dev    See {_bet}.
     */
    function betNative(uint256 conditionId, uint64 outcome) external payable {
        IWNative(token).deposit{value: msg.value}();
        _bet(conditionId, outcome, uint128(msg.value));
    }

    /**
     * @notice Bet `amount` tokens that in the condition `conditionId` will happen outcome with id `outcome`.
     * @dev    Minted tokenId = 2 * `conditionId` + index of outcome `outcome` in condition struct.
     * @param  conditionId the match or game id
     * @param  outcome id of predicted outcome
     * @param  amount bet amount in tokens
     */
    function _bet(
        uint256 conditionId,
        uint64 outcome,
        uint128 amount
    ) internal {
        if (amount == 0) revert AmountMustNotBeZero();

        Condition storage condition = getCondition(conditionId);

        if (conditionIsCanceled(conditionId))
            revert ConditionCanceled_(conditionId);
        if (block.timestamp >= condition.timestamp)
            revert ConditionStarted(conditionId);
        outcomeIsCorrect(condition, outcome);

        uint256 tokenId = conditionId *
            2 -
            (outcome == condition.outcomes[0] ? 1 : 0);
        condition.totalNetBets[(tokenId + 1) % 2] += amount;
        super._mint(msg.sender, tokenId, amount, "");

        emit NewBet(msg.sender, tokenId, conditionId, outcome, amount);
    }

    /**
     * @notice Get token id of bet on outcome `outcome` in condition `conditionId`.
     * @param  conditionId the match or game id
     * @param  outcome id of predicted outcome
     * @return bet token id
     */
    function getTokenId(uint256 conditionId, uint64 outcome)
        public
        view
        returns (uint256)
    {
        Condition memory condition = getCondition(conditionId);

        outcomeIsCorrect(condition, outcome);

        return conditionId * 2 - (outcome == condition.outcomes[0] ? 1 : 0);
    }

    /**
     * @notice Withdraw payout based on bet with AzuroBet token `tokenId` in finished or cancelled condition.
     * @param  tokenIds array of bet tokens ids withdraw payout to
     */
    function withdrawPayout(uint256[] calldata tokenIds) external {
        TransferHelper.safeTransfer(
            token,
            msg.sender,
            _withdrawPayout(tokenIds)
        );
    }

    /**
     * @notice Withdraw payout in native token based on bet with AzuroBet token `tokenId` in finished or cancelled condition.
     * @param  tokenIds array of bet tokens ids withdraw payout to
     */
    function withdrawPayoutNative(uint256[] calldata tokenIds) external {
        uint256 amount = _withdrawPayout(tokenIds);
        IWNative(token).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    /**
     * @notice Withdraw payout based on bets in finished or cancelled conditions.
     * @param  tokenIds array of bet tokens ids withdraw payout to
     */
    function _withdrawPayout(uint256[] calldata tokenIds)
        internal
        returns (uint256 totalPayout)
    {
        uint256 refunds;
        uint256 conditionId;
        uint256 tokenId;
        uint256 balance;
        uint256 outcomeWinIndex;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            tokenId = tokenIds[i];
            balance = super.balanceOf(msg.sender, tokenId);

            if (balance == 0) revert ZeroBalance(tokenId);

            conditionId = (tokenId + 1) / 2;
            Condition memory condition = getCondition(conditionId);

            if (
                condition.state != ConditionState.RESOLVED &&
                !conditionIsCanceled(conditionId)
            ) revert ConditionStillOn(conditionId);

            super._burn(msg.sender, tokenId, balance);

            outcomeWinIndex = (tokenId + 1) % 2; // uint256 used to reduce gas consumption
            if (condition.state == ConditionState.RESOLVED) {
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
            (totalPayout * (multiplier - daoFee)) /
            multiplier +
            refunds;
    }

    /**
     * @notice Reward contract owner (DAO) with total amount of charged fees.
     */
    function claimDAOReward() external {
        if (DAOReward == 0) revert NoDAOReward();

        uint128 reward = DAOReward;
        DAOReward = 0;
        TransferHelper.safeTransfer(token, owner(), reward);
    }
}
