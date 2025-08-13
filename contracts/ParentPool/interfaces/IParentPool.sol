// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBase} from "../../Base/interfaces/IBase.sol";

interface IParentPool {
    struct Deposit {
        uint256 liquidityTokenAmountToDeposit;
        address lp;
    }

    struct Withdrawal {
        uint256 lpTokenAmountToWithdraw;
        address lp;
    }

    struct PendingWithdrawal {
        uint256 liqTokenAmountToWithdraw;
        uint256 lpTokenAmountToWithdraw;
        address lp;
    }

    struct ChildPoolSnapshot {
        uint256 balance;
        // TODO: flat this structure
        IBase.LiqTokenDailyFlow dailyFlow;
        uint256 iouTotalSent;
        uint256 iouTotalReceived;
        uint256 iouTotalSupply;
        uint256 totalLiqTokenSent;
        uint256 totalLiqTokenReceived;
        uint32 timestamp;
    }

    error DepositQueueIsFull();
    error WithdrawalQueueIsFull();
    error QueuesAreNotFull();
    error LiquidityCapReached(uint256 liqCapAmount);

    event DepositQueued(bytes32 indexed depositId, address indexed lp, uint256 amount);
    event WithdrawalQueued(bytes32 indexed withdrawId, address indexed lp, uint256 liqTokenAmount);
    event SnapshotReceived(
        bytes32 indexed messageId,
        uint24 indexed sourceChainSelector,
        ChildPoolSnapshot snapshot
    );
}
