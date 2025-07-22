// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPoolBase {
    struct LiqTokenAmountFlow {
        uint256 inflow;
        uint256 outflow;
    }

    enum ConceroMessageType {
        UPDATE_TARGET_BALANCE
    }
}
