// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";

contract ChildPool is Rebalancer {
    using s for s.ChildPool;

    constructor(
        address conceroRouter,
        address iouToken,
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    )
        PoolBase(liquidityToken, conceroRouter, iouToken, liquidityTokenDecimals, chainSelector)
        Rebalancer()
    {}
}
