// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPoolBase {
    enum ConceroMessageType {
        BRIDGE_IOU,
        UPDATE_TARGET_BALANCE,
        SEND_SNAPSHOT,
        BRIDGE
    }

    struct LiqTokenDailyFlow {
        uint256 inflow;
        uint256 outflow;
    }
}
