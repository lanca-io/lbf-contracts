// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface ILancaClient {
    function lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        bytes32 sender,
        uint256 amount,
        bytes calldata payload
    ) external;
}
