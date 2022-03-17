// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

interface ITotoBet {
    function updateCore(address core_, bool active_) external;

    function getTokenID(
        address core_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_
    ) external view returns (uint256);

    function balanceOf(address account, uint256 conditionOutcomeID_)
        external
        view
        returns (uint256);

    function mint(
        address account_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint128 amount_
    ) external returns (uint256);

    function burn(
        address account_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint256 amount_
    ) external;
}
