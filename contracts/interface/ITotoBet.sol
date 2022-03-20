// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.3;

interface ITotoBet {
    function updateCore(address core_, bool active_) external;

    function mint(
        address to_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_,
        uint128 amount_
    ) external returns (uint256 tokenID);

    function burnAll(
        address from_,
        uint256 coreConditionID_,
        uint8 outcomeIndex_
    ) external returns (uint256, uint256);

    function burnAll(
        address from_,
        uint256[] memory coreConditionsIDs_,
        uint8[] memory outcomesIndices_
    ) external returns (uint256[] memory, uint256[] memory);
}
