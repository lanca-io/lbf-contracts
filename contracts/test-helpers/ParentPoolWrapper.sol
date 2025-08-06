// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ParentPool} from "../ParentPool/ParentPool.sol";
import {LPToken} from "../ParentPool/LPToken.sol";
import {IParentPool} from "../ParentPool/interfaces/IParentPool.sol";
import {Storage as s} from "../PoolBase/libraries/Storage.sol";
import {Storage as pps} from "../ParentPool/libraries/Storage.sol";

contract ParentPoolWrapper is ParentPool {
    using s for s.PoolBase;
    using s for pps.ParentPool;

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

    // Expose internal functions for testing
    function setTargetBalance(uint256 newTargetBalance) external {
        s.poolBase().targetBalance = newTargetBalance;
    }

    function exposed_setTargetBalance(uint256 newTargetBalance) external {
        s.poolBase().targetBalance = newTargetBalance;
    }
}
