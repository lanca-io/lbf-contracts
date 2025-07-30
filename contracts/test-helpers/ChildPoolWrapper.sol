// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ChildPool} from "../ChildPool/ChildPool.sol";

contract ChildPoolWrapper is ChildPool {
    constructor(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector,
        address iouToken,
        address conceroRouter
    ) ChildPool(liquidityToken, liquidityTokenDecimals, chainSelector, iouToken, conceroRouter) {}

    // Expose internal functions for testing
    function setTargetBalance(uint256 newTargetBalance) external {
        _setTargetBalance(newTargetBalance);
    }
}
