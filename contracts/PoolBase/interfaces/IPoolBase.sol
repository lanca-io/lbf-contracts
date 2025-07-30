// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPoolBase {
    enum ConceroMessageType {
        UPDATE_TARGET_BALANCE
    }

    struct LiqTokenDailyFlow {
        uint256 inflow;
        uint256 outflow;
    }
}
