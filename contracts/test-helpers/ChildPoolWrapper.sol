// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ChildPool} from "../ChildPool/ChildPool.sol";
import {Storage as s} from "../PoolBase/libraries/Storage.sol";

contract ChildPoolWrapper is ChildPool {
    using s for s.PoolBase;

    constructor(
        address conceroRouter,
        address iouToken,
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) ChildPool(conceroRouter, iouToken, liquidityToken, liquidityTokenDecimals, chainSelector) {}

    // Expose internal functions for testing
    function setTargetBalance(uint256 newTargetBalance) external {
        s.poolBase().targetBalance = newTargetBalance;
    }
}
