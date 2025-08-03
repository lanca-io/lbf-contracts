// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";

contract ParentPoolHarness is ParentPool {
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
}
