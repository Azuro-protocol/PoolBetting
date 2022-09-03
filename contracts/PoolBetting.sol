// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "./interface/IPoolBetting.sol";
import "./interface/IWNative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

/// @title Azuro Totalizator
contract PoolBetting is OwnableUpgradeable, ERC1155Upgradeable, IPoolBetting {
    uint48 constant multiplier = 10**12;

    uint256 public lastConditionId;
    mapping(uint256 => Condition) public conditions;

    address public token;
    /**
     * @notice The condition expires if during this time before it starts there were no bets on one of the outcomes.
     */
    uint64 public expireTimer;

    uint128 public daoFee;
    uint128 public DAOReward;

    receive() external payable {
        assert(msg.sender == token); // only accept native tokens via fallback from the WETH contract
    }

    /**
     * @param  token_ address of the token used in bets and rewards
     * @param  fee bet fee in decimals 10^9
     */
    function initialize(address token_, uint128 fee)
        external
        virtual
        initializer
    {
        if (token_ == address(0)) revert WrongToken();
        if (fee >= multiplier) revert WrongFee();

        __Ownable_init();
        __ERC1155_init("Pool Betting");
        token = token_;
        expireTimer = 600;
        daoFee = fee;
    }

    /**
     * @notice Provide information about current condition.
     * @param  outcomes outcome ids for this condition [outcome 1, outcome 2]
     * @param  startsAt time when match starts and bets not allowed
     * @param  ipfsHash detailed info about match stored in IPFS
     */
    function createCondition(
        uint64[2] calldata outcomes,
        uint64 startsAt,
        bytes32 ipfsHash
    ) external {
        if (outcomes[0] == outcomes[1]) revert SameOutcomes();
        if (startsAt <= block.timestamp + expireTimer)
            revert ConditionExpired();

        uint256 conditionId = ++lastConditionId;

        Condition storage newCondition = conditions[conditionId];
        newCondition.oracle = msg.sender;
        newCondition.outcomes = outcomes;
        newCondition.startsAt = startsAt;
        newCondition.ipfsHash = ipfsHash;

        emit ConditionCreated(msg.sender, conditionId, startsAt);
    }

    /**
     * @notice  Oracle: Indicate the condition `conditionId` as canceled.
     * @param   conditionId the current match or game id
     */
    function cancelCondition(uint256 conditionId) external {
        Condition storage condition = _getCondition(conditionId);
        _onlyOracle(condition);

        if (condition.state == ConditionState.RESOLVED)
            revert ConditionResolved_(conditionId);
        if (condition.state == ConditionState.CANCELED)
            revert ConditionAlreadyCanceled(conditionId);

        condition.state = ConditionState.CANCELED;

        emit ConditionCanceled(conditionId);
    }

    /**
     * @notice Oracle: Indicate outcome `outcomeWin` as happened in oracle's condition `conditionId`.
     * @param  conditionId the match or game id
     * @param  outcomeWin id of happened outcome
     */
    function resolveCondition(uint256 conditionId, uint64 outcomeWin) external {
        Condition storage condition = _getCondition(conditionId);
        _onlyOracle(condition);

        if (_isConditionCanceled(conditionId))
            revert ConditionCanceled_(conditionId);
        if (condition.state != ConditionState.CREATED)
            revert ConditionAlreadyResolved(conditionId);
        if (block.timestamp < condition.startsAt)
            revert ConditionNotStarted(conditionId);

        _outcomeIsCorrect(condition, outcomeWin);

        DAOReward +=
            ((condition.totalNetBets[0] + condition.totalNetBets[1]) * daoFee) /
            multiplier;

        condition.outcomeWin = outcomeWin;
        condition.state = ConditionState.RESOLVED;

        emit ConditionResolved(conditionId, outcomeWin);
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
     * @notice Withdraw payout based on bet with AzuroBet token `tokenId` in finished or cancelled condition.
     * @param  tokenIds array of bet tokens ids withdraw payout to
     */
    function withdrawPayout(uint256[] calldata tokenIds) external {
        TransferHelper.safeTransfer(
            token,
            msg.sender,
            _resolvePayout(tokenIds)
        );
    }

    /**
     * @notice Withdraw payout in native token based on bet with AzuroBet token `tokenId` in finished or cancelled condition.
     * @param  tokenIds array of bet tokens ids withdraw payout to
     */
    function withdrawPayoutNative(uint256[] calldata tokenIds) external {
        uint128 amount = _resolvePayout(tokenIds);
        IWNative(token).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
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

    /**
     * @notice Get condition with id `conditionId`.
     * @param  conditionId the match or game id
     * @return the match or game struct
     */
    function getCondition(uint256 conditionId)
        external
        view
        returns (Condition memory)
    {
        return _getCondition(conditionId);
    }

    /**
     * @notice View payout based on bets in finished or cancelled conditions.
     * @param  tokenIds array of bet tokens ids view payout to
     * @return payout unclaimed winnings of the owner of the token
     */
    function viewPayout(uint256[] calldata tokenIds) public returns (uint128) {
        uint256 payout;
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
            Condition memory condition = _getCondition(conditionId);

            if (
                condition.state != ConditionState.RESOLVED &&
                !_isConditionCanceled(conditionId)
            ) revert ConditionStillOn(conditionId);

            outcomeWinIndex = (tokenId + 1) % 2; // uint256 used to reduce gas consumption
            if (condition.state == ConditionState.RESOLVED) {
                if (
                    condition.outcomes[outcomeWinIndex] == condition.outcomeWin
                ) {
                    payout +=
                        ((condition.totalNetBets[0] +
                            condition.totalNetBets[1]) * balance) /
                        condition.totalNetBets[outcomeWinIndex];
                }
            } else {
                refunds += balance;
            }
        }
        payout = (payout * (multiplier - daoFee)) / multiplier + refunds;

        return uint128(payout);
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
        Condition memory condition = _getCondition(conditionId);

        _outcomeIsCorrect(condition, outcome);

        return conditionId * 2 - (outcome == condition.outcomes[0] ? 1 : 0);
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

        Condition storage condition = _getCondition(conditionId);

        if (_isConditionCanceled(conditionId))
            revert ConditionCanceled_(conditionId);
        if (block.timestamp >= condition.startsAt)
            revert ConditionStarted(conditionId);
        _outcomeIsCorrect(condition, outcome);

        uint256 tokenId = conditionId *
            2 -
            (outcome == condition.outcomes[0] ? 1 : 0);
        condition.totalNetBets[(tokenId + 1) % 2] += amount;
        super._mint(msg.sender, tokenId, amount, "");

        emit NewBet(msg.sender, tokenId, conditionId, outcome, amount);
    }

    /**
     * @notice Check if the condition `conditionId` is canceled.
     * @dev    Previously cancel the condition if during `expireTime` sec before it starts there are no bets on one of the outcomes.
     * @param  conditionId the match or game id
     * @return true if the condition is canceled else false
     */
    function _isConditionCanceled(uint256 conditionId) internal returns (bool) {
        Condition storage condition = _getCondition(conditionId);

        if (condition.state == ConditionState.CANCELED) {
            return true;
        }
        if (
            (block.timestamp + expireTimer >= condition.startsAt) &&
            (condition.totalNetBets[0] == 0 || condition.totalNetBets[1] == 0)
        ) {
            condition.state = ConditionState.CANCELED;

            emit ConditionCanceled(conditionId);

            return true;
        }
        return false;
    }

    /**
     * @notice Resolve payout based on bets in finished or cancelled conditions.
     * @param  tokenIds array of bet tokens ids withdraw payout to
     * @return payout winnings of the owner of the token
     */
    function _resolvePayout(uint256[] calldata tokenIds)
        internal
        returns (uint128 payout)
    {
        payout = viewPayout(tokenIds);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            _burnAll(msg.sender, tokenIds[i]);
        }
        emit BettorWin(msg.sender, tokenIds, payout);
    }

    /**
     * @notice Burn all of tokens type `id` owned by address `from`.
     * @notice See {IERC1155-_burn}.
     * @param  from token recipient
     * @param  tokenId token type ID
     */
    function _burnAll(address from, uint256 tokenId) internal {
        super._burn(from, tokenId, super.balanceOf(from, tokenId));
    }

    /**
     * @notice Get condition with id `conditionId`.
     * @param  conditionId the match or game id
     * @return the match or game struct
     */
    function _getCondition(uint256 conditionId)
        internal
        view
        returns (Condition storage)
    {
        Condition storage condition = conditions[conditionId];
        if (condition.startsAt == 0) revert ConditionNotExists(conditionId);

        return condition;
    }

    /**
     * @notice Throws if function was not called by oracle.
     * @param  condition the match or game struct
     */
    function _onlyOracle(Condition memory condition) internal view {
        if (condition.oracle != msg.sender) revert OnlyOracle();
    }

    /**
     * @notice Throws if the condition `conditionId` have not outcome `outcome` as possible.
     * @param  condition the match or game struct
     * @param  outcome outcome id
     */
    function _outcomeIsCorrect(Condition memory condition, uint64 outcome)
        internal
        pure
    {
        if (
            outcome != condition.outcomes[0] && outcome != condition.outcomes[1]
        ) revert WrongOutcome();
    }
}
