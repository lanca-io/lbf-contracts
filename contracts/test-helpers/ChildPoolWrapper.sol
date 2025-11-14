// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ChildPool} from "../ChildPool/ChildPool.sol";
import {Storage as s} from "../Base/libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";

contract ChildPoolWrapper is ChildPool {
    using s for s.Base;
    using s for rs.Rebalancer;

    constructor(
        address conceroRouter,
        address iouToken,
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector,
        uint24 parentPoolChainSelector
    )
        ChildPool(
            conceroRouter,
            iouToken,
            liquidityToken,
            liquidityTokenDecimals,
            chainSelector,
            parentPoolChainSelector
        )
    {}

    // Expose internal functions for testing
    function setTargetBalance(uint256 newTargetBalance) external {
        s.base().targetBalance = newTargetBalance;
    }

    function setDailyFlow(uint256 inflow, uint256 outflow) external {
        s.base().flowByDay[getYesterdayStartTimestamp()].inflow = inflow;
        s.base().flowByDay[getYesterdayStartTimestamp()].outflow = outflow;
    }

    function setTotalIouSent(uint256 totalIouSent) external {
        rs.rebalancer().totalIouSent = totalIouSent;
    }

    function setTotalIouReceived(uint256 totalIouReceived) external {
        rs.rebalancer().totalIouReceived = totalIouReceived;
    }
}
