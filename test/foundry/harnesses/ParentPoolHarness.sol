// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {Storage as s} from "../../../contracts/ParentPool/libraries/Storage.sol";

contract ParentPoolHarness is ParentPool {
    using s for s.ParentPool;

    constructor(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        address lpToken,
        address conceroRouter,
        uint24 chainSelector,
        address iouToken
    )
        ParentPool(
            liquidityToken,
            liquidityTokenDecimals,
            lpToken,
            conceroRouter,
            chainSelector,
            iouToken
        )
    {}

    function exposed_setChildPoolSnapshot(
        uint24 chainSelector,
        SnapshotSubmission memory snapshot
    ) public {
        s.parentPool().childPoolsSubmissions[chainSelector] = snapshot;
    }
}
