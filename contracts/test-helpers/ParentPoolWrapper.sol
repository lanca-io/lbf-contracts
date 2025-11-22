// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ParentPool} from "../ParentPool/ParentPool.sol";
import {Storage as s} from "../Base/libraries/Storage.sol";
import {Storage as pps} from "../ParentPool/libraries/Storage.sol";

contract ParentPoolWrapper is ParentPool {
    using s for s.Base;
    using s for pps.ParentPool;

    constructor(
        address liquidityToken,
        address lpToken,
        address iouToken,
        address conceroRouter,
        uint24 chainSelector,
        uint256 minTargetBalance
    )
        ParentPool(
            liquidityToken,
            lpToken,
            iouToken,
            conceroRouter,
            chainSelector,
            minTargetBalance
        )
    {}

    // Expose internal functions for testing
    function setTargetBalance(uint256 newTargetBalance) external {
        s.base().targetBalance = newTargetBalance;
    }

    function exposed_setTargetBalance(uint256 newTargetBalance) external {
        s.base().targetBalance = newTargetBalance;
    }
}
