// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPoolBase} from "../../PoolBase/interfaces/IPoolBase.sol";

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

    struct SnapshotSubmission {
        uint256 balance;
        IPoolBase.LiqTokenDailyFlow dailyFlow;
        uint256 iouTotalSent;
        uint256 iouTotalReceived;
        uint256 iouTotalSupply;
        uint32 timestamp;
    }

    error DepositQueueIsFull();
    error WithdrawalQueueIsFull();
    error QueuesAreNotFull();

    event DepositQueued(bytes32 indexed depositId, address indexed lp, uint256 amount);
    event WithdrawQueued(bytes32 indexed withdrawId, address indexed lp, uint256 liqTokenAmount);
    event SnapshotReceived(
        bytes32 indexed messageId,
        uint24 indexed sourceChainSelector,
        SnapshotSubmission snapshot
    );
}
