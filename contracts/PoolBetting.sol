// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "./interface/IPoolBetting.sol";
import "./interface/IWNative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

/// @title Azuro Totalizator
contract PoolBetting is OwnableUpgradeable, ERC1155Upgradeable, IPoolBetting {
    uint48 constant MULTIPLIER = 10**12;

    uint256 public lastConditionId;
    mapping(uint256 => Condition) public conditions;

    address public token;
    /**
     * @notice The condition expires if during this time before it starts there were no bets on one of the outcomes.
     */
    uint64 public expireTimer;

    uint64 public daoFee;
    uint128 public daoReward;

    receive() external payable {
        assert(msg.sender == token);
    }

    function initialize(address token_, uint64 fee)
        external
        virtual
        initializer
    {
        if (token_ == address(0)) revert WrongToken();
        if (fee >= MULTIPLIER) revert WrongFee();

        __Ownable_init();
        __ERC1155_init("Pool Betting");
        token = token_;
        expireTimer = 600;
        daoFee = fee;
    }

    /**
     * @notice Provide information about current condition.
     * @param  ipfsHash detailed info about match stored in IPFS
     * @param  bettingStartsAt time after betting in allowed
     * @param  startsAt time after betting in not allowed
     */
    function createCondition(
        bytes32 ipfsHash,
        uint64 startsAt,
        uint64 bettingStartsAt
    ) external {
        if (bettingStartsAt >= startsAt) revert IncorrectBettingPeriod();
        if (
            startsAt <= block.timestamp + expireTimer ||
            startsAt <= bettingStartsAt + expireTimer
        ) revert ConditionExpired();

        uint256 conditionId = ++lastConditionId;

        Condition storage newCondition = conditions[conditionId];
        newCondition.oracle = msg.sender;
        newCondition.bettingStartsAt = bettingStartsAt;
        newCondition.startsAt = startsAt;
        newCondition.ipfsHash = ipfsHash;

        emit ConditionCreated(
            msg.sender,
            conditionId,
            startsAt,
            bettingStartsAt
        );
    }

    /**
     * @notice  Oracle: Indicate the condition `conditionId` as canceled.
     * @param   conditionId the current match or game id
     */
    function cancelCondition(uint256 conditionId) external {
        Condition storage condition = _getCondition(conditionId);
        _onlyOracle(condition);

        if (condition.state == ConditionState.RESOLVED)
            revert ConditionResolved_();
        if (condition.state == ConditionState.CANCELED)
            revert ConditionAlreadyCanceled();

        condition.state = ConditionState.CANCELED;

        emit ConditionCanceled(conditionId);
    }

    /**
     * @notice Oracle: Indicate outcome `outcomeWin` as happened in oracle's condition `conditionId`.
     * @param  conditionId the match or game id
     * @param  outcomeWin id of happened outcome {1, 2}
     */
    function resolveCondition(uint256 conditionId, uint8 outcomeWin) external {
        Condition storage condition = _getCondition(conditionId);
        _onlyOracle(condition);

        _conditionNotCanceled(condition);
        if (condition.state == ConditionState.RESOLVED)
            revert ConditionAlreadyResolved();

        uint64 startsAt = condition.startsAt;
        if (block.timestamp < startsAt) revert ConditionNotStarted(startsAt);

        _outcomeIsCorrect(outcomeWin);

        daoReward += uint128(
            (uint256(condition.totalNetBets[0] + condition.totalNetBets[1]) *
                daoFee) / MULTIPLIER
        );

        condition.outcomeWin = outcomeWin;
        condition.state = ConditionState.RESOLVED;

        emit ConditionResolved(conditionId, outcomeWin);
    }

    /**
     * @notice Oracle: Set `startsAt` as new condition `conditionId` start time.
     * @param  conditionId the match or game id
     * @param  startsAt new condition start time
     */
    function shiftCondition(
        uint256 conditionId,
        uint64 startsAt,
        uint64 bettingStartsAt
    ) external {
        Condition storage condition = _getCondition(conditionId);
        _onlyOracle(condition);

        if (condition.state == ConditionState.RESOLVED)
            revert ConditionResolved_();
        if (condition.state == ConditionState.CANCELED)
            revert ConditionCanceled_();
        if (bettingStartsAt >= startsAt) revert IncorrectBettingPeriod();
        if (
            (condition.totalNetBets[0] == 0 ||
                condition.totalNetBets[1] == 0) &&
            (startsAt <= block.timestamp + expireTimer ||
                startsAt <= bettingStartsAt + expireTimer)
        ) revert ConditionExpiredAfterShift();

        condition.startsAt = startsAt;
        condition.bettingStartsAt = bettingStartsAt;

        emit ConditionShifted(conditionId, startsAt, bettingStartsAt);
    }

    /**
     * @notice Bet `amount` tokens that in the condition `conditionId` will happen outcome `outcome`.
     * @dev    See {_bet}.
     */
    function bet(
        uint256 conditionId,
        uint8 outcome,
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
     * @notice Bet transferred native tokens that in the condition `conditionId` will happen outcome `outcome`.
     * @dev    See {_bet}.
     */
    function betNative(uint256 conditionId, uint8 outcome) external payable {
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
    function claimDaoReward() external {
        if (daoReward == 0) revert NoDaoReward();

        uint128 reward = daoReward;
        daoReward = 0;
        TransferHelper.safeTransfer(token, owner(), reward);
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
        uint256 outcome;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            tokenId = tokenIds[i];
            balance = super.balanceOf(msg.sender, tokenId);

            if (balance == 0) revert ZeroBalance(tokenId);

            conditionId = tokenId / 10;
            Condition storage condition = _getCondition(conditionId);

            if (condition.state == ConditionState.CREATED) {
                if (!_isConditionExpired(condition))
                    revert ConditionStillOn(conditionId);

                condition.state = ConditionState.CANCELED;
                emit ConditionCanceled(conditionId);
            }
            if (condition.state == ConditionState.CANCELED) {
                refunds += balance;
                continue;
            }
            outcome = tokenId % 10;
            if (outcome == condition.outcomeWin)
                payout +=
                    ((condition.totalNetBets[0] + condition.totalNetBets[1]) *
                        balance) /
                    condition.totalNetBets[outcome - 1];
        }

        return uint128((payout * (MULTIPLIER - daoFee)) / MULTIPLIER + refunds);
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
     * @notice Bet `amount` tokens that in the condition `conditionId` will happen outcome with id `outcome`.
     * @dev    Minted tokenId equals concatenation of `conditionId` and `outcome`.
     * @param  conditionId the match or game id
     * @param  outcome id of predicted outcome
     * @param  amount bet amount in tokens
     */
    function _bet(
        uint256 conditionId,
        uint8 outcome,
        uint128 amount
    ) internal {
        Condition storage condition = _getCondition(conditionId);
        if (amount == 0) revert AmountMustNotBeZero();

        _conditionNotCanceled(condition);
        if (condition.state == ConditionState.RESOLVED)
            revert ConditionResolved_();

        uint64 startsAt = condition.startsAt;
        if (block.timestamp >= startsAt) revert BettingEnded(startsAt);

        uint64 bettingStartsAt = condition.bettingStartsAt;
        if (block.timestamp < bettingStartsAt)
            revert BettingNotStarted(bettingStartsAt);

        uint256 tokenId = getTokenId(conditionId, outcome);
        super._mint(msg.sender, tokenId, amount, "");
        condition.totalNetBets[outcome - 1] += amount;

        emit NewBet(msg.sender, tokenId, conditionId, outcome, amount);
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
     * @notice Get token id of bet on outcome `outcome` in condition `conditionId`.
     * @param  conditionId the match or game id
     * @param  outcome id of predicted outcome
     * @return bet token id
     */
    function getTokenId(uint256 conditionId, uint8 outcome)
        public
        pure
        returns (uint256)
    {
        _outcomeIsCorrect(outcome);
        return conditionId * 10 + outcome;
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
     * @notice Throw if condition is canceled (expired).
     */
    function _conditionNotCanceled(Condition storage condition) internal view {
        if (
            condition.state == ConditionState.CANCELED ||
            _isConditionExpired(condition)
        ) revert ConditionCanceled_();
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
        if (condition.oracle == address(0)) revert ConditionNotExists();

        return condition;
    }

    /**
     * @notice Check if the condition is expired.
     * @notice Condition is expired if if during `expireTime` sec before it starts there are no bets for one of its outcomes.
     */
    function _isConditionExpired(Condition storage condition)
        internal
        view
        returns (bool)
    {
        return
            (block.timestamp + expireTimer >= condition.startsAt) &&
            (condition.totalNetBets[0] == 0 || condition.totalNetBets[1] == 0);
    }

    /**
     * @notice Throws if function was not called by oracle.
     * @param  condition the match or game struct
     */
    function _onlyOracle(Condition memory condition) internal view {
        if (condition.oracle != msg.sender) revert OnlyOracle();
    }

    /**
     * @notice Throws if the `outcome` not belongs to {1, 2}.
     * @param  outcome outcome id
     */
    function _outcomeIsCorrect(uint8 outcome) internal pure {
        if (outcome != 1 && outcome != 2) revert WrongOutcome();
    }
}
