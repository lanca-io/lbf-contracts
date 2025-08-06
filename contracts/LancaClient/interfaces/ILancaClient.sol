// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface ILancaClient {
    function lancaReceive(address token, address from, uint256 value, bytes memory data) external;
}
