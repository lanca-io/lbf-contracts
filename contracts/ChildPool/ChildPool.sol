// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";

contract ChildPool is Rebalancer {
    using s for s.ChildPool;

    constructor(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector,
        address iouToken,
        address conceroRouter
    ) PoolBase(liquidityToken, liquidityTokenDecimals, chainSelector) Rebalancer(iouToken, conceroRouter) {}
}
