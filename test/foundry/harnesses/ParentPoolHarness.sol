// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {Storage as s} from "../../../contracts/ParentPool/libraries/Storage.sol";
import {Storage as pbs} from "../../../contracts/PoolBase/libraries/Storage.sol";

contract ParentPoolHarness is ParentPool {
    using s for s.ParentPool;

    constructor(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        address lpToken,
        address conceroRouter,
        uint24 chainSelector,
        address iouToken,
        uint256 minTargetBalance
    )
        ParentPool(
            liquidityToken,
            liquidityTokenDecimals,
            lpToken,
            conceroRouter,
            chainSelector,
            iouToken,
            minTargetBalance
        )
    {}

    /* GETTERS */

    function exposed_getChildPoolTargetBalance(uint24 chainSelector) public view returns (uint256) {
        return s.parentPool().childPoolTargetBalances[chainSelector];
    }

    function exposed_getChildPoolSnapshot(
        uint24 chainSelector
    ) public view returns (SnapshotSubmission memory) {
        return s.parentPool().childPoolsSubmissions[chainSelector];
    }

    /* SETTERS */

    function exposed_setChildPoolSnapshot(
        uint24 chainSelector,
        SnapshotSubmission memory snapshot
    ) public {
        s.parentPool().childPoolsSubmissions[chainSelector] = snapshot;
    }

    function exposed_setTargetBalance(uint256 targetBalance) public {
        pbs.poolBase().targetBalance = targetBalance;
    }

    function exposed_setChildPoolTargetBalance(uint24 chainSelector, uint256 targetBalance) public {
        s.parentPool().childPoolTargetBalances[chainSelector] = targetBalance;
    }

    function exposed_setYesterdayFlow(uint256 inflow, uint256 outflow) public {
        pbs.poolBase().flowByDay[getYesterdayStartTimestamp()].inflow = inflow;
        pbs.poolBase().flowByDay[getYesterdayStartTimestamp()].outflow = outflow;
    }
}
