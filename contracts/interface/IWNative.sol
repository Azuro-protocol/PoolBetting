// SPDX-License-Identifier: GPL-3.0
/**
 * @dev interrface for canonical wrapped native contract vbased on WETH9.sol
 */
pragma solidity ^0.8.4;

interface IWNative {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}
