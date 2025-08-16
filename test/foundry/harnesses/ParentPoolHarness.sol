// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {Storage as s} from "../../../contracts/ParentPool/libraries/Storage.sol";
import {Storage as pbs} from "../../../contracts/Base/libraries/Storage.sol";
import {Storage as bs} from "../../../contracts/LancaBridge/libraries/Storage.sol";
import {Storage as rs} from "../../../contracts/Rebalancer/libraries/Storage.sol";

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
    ) public view returns (ChildPoolSnapshot memory) {
        return s.parentPool().childPoolSnapshots[chainSelector];
    }

    function exposed_getSentNonce(uint24 dstChainSelector) external view returns (uint256) {
        return bs.bridge().sentNonces[dstChainSelector];
    }

    function exposed_getTotalSent() external view returns (uint256) {
        return bs.bridge().totalSent;
    }

    function exposed_getTotalReceived() external view returns (uint256) {
        return bs.bridge().totalReceived;
    }

    function exposed_getReceivedBridgeAmount(
        uint24 srcChainSelector,
        uint256 nonce
    ) external view returns (uint256) {
        return bs.bridge().receivedBridges[srcChainSelector][nonce];
    }

    /* SETTERS */

    function exposed_setChildPoolSnapshot(
        uint24 chainSelector,
        ChildPoolSnapshot memory snapshot
    ) public {
        s.parentPool().childPoolSnapshots[chainSelector] = snapshot;
    }

    function exposed_setTargetBalance(uint256 targetBalance) public {
        pbs.base().targetBalance = targetBalance;
    }

    function exposed_setChildPoolTargetBalance(uint24 chainSelector, uint256 targetBalance) public {
        s.parentPool().childPoolTargetBalances[chainSelector] = targetBalance;
    }

    function exposed_setYesterdayFlow(uint256 inflow, uint256 outflow) public {
        pbs.base().flowByDay[getYesterdayStartTimestamp()].inflow = inflow;
        pbs.base().flowByDay[getYesterdayStartTimestamp()].outflow = outflow;
    }

    function exposed_getConceroRouter() public view returns (address) {
        return i_conceroRouter;
    }

    function exposed_setTotalRebalancerFee(uint256 rebalancerFee) public {
        rs.rebalancer().totalRebalancingFee = rebalancerFee;
    }
}
