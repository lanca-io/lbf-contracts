// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ChildPool} from "../ChildPool/ChildPool.sol";
import {Storage as s} from "../PoolBase/libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";

contract ChildPoolWrapper is ChildPool {
    using s for s.PoolBase;
    using s for rs.Rebalancer;

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

    function setDailyFlow(uint256 inflow, uint256 outflow) external {
        s.poolBase().flowByDay[getYesterdayStartTimestamp()].inflow = inflow;
        s.poolBase().flowByDay[getYesterdayStartTimestamp()].outflow = outflow;
    }

    function setTotalIouSent(uint256 totalIouSent) external {
        rs.rebalancer().totalIouSent = totalIouSent;
    }

    function setTotalIouReceived(uint256 totalIouReceived) external {
        rs.rebalancer().totalIouReceived = totalIouReceived;
    }
}
