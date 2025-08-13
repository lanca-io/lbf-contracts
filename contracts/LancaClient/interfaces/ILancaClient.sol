// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface ILancaClient {
    function lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        address from,
        uint256 amount,
        bytes memory data
    ) external;
}
