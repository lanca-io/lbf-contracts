// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBase} from "../../Base/interfaces/IBase.sol";

/// @title IParentPool
/// @notice Interface for the Lanca parent pool on the main (parent) chain.
/// @dev
/// - The parent pool:
///   * aggregates liquidity from LPs,
///   * coordinates liquidity distribution between child pools,
///   * manages deposit / withdrawal queues,
///   * tracks child pool snapshots and calculates target balances.
/// - This interface defines shared types, events and errors used by the parent pool
///   but does not expose behavior itself (no functions here).
interface IParentPool {
    /// @notice Pending deposit information stored in the deposit queue.
    /// @dev
    /// - `liquidityTokenAmountToDeposit` is the amount of liquidity tokens enqueued by the LP.
    /// - `lp` is the address of the liquidity provider.
    struct Deposit {
        uint256 liquidityTokenAmountToDeposit;
        address lp;
    }

    /// @notice Pending withdrawal information stored in the withdrawal queue.
    /// @dev
    /// - `lpTokenAmountToWithdraw` is the amount of LP tokens the user wants to redeem.
    /// - `lp` is the address of the liquidity provider.
    struct Withdrawal {
        uint256 lpTokenAmountToWithdraw;
        address lp;
    }

    /// @notice Withdrawal information that has been processed by the queue and is pending execution.
    /// @dev
    /// - `liqTokenAmountToWithdraw` is the underlying liquidity amount reserved for withdrawal
    ///   (before fees are applied in `processPendingWithdrawals`).
    /// - `lpTokenAmountToWithdraw` is the LP token amount that will be burned once the withdrawal is executed.
    /// - `lp` is the beneficiary of the withdrawal.
    struct PendingWithdrawal {
        uint256 liqTokenAmountToWithdraw;
        uint256 lpTokenAmountToWithdraw;
        address lp;
    }

    /// @notice Snapshot of a child pool’s state used for global rebalance calculations.
    /// @dev
    /// - All amounts are stored in a unified internal decimal format (implementation-dependent),
    ///   and may need to be rescaled for external presentation.
    /// - `dailyFlow` encapsulates inflow/outflow for the last day in terms of the liquidity token.
    struct ChildPoolSnapshot {
        /// @notice Child pool active liquidity balance at the time of snapshot.
        uint256 balance;
        /// @notice Daily inflow/outflow metrics for the child pool.
        IBase.LiqTokenDailyFlow dailyFlow;
        /// @notice Total IOU amount sent from this child pool to other pools.
        uint256 iouTotalSent;
        /// @notice Total IOU amount received by this child pool from other pools.
        uint256 iouTotalReceived;
        /// @notice Total IOU token supply on this child pool at the time of snapshot.
        uint256 iouTotalSupply;
        /// @notice Total liquidity tokens sent out from this child pool through bridge operations.
        uint256 totalLiqTokenSent;
        /// @notice Total liquidity tokens received by this child pool through bridge operations.
        uint256 totalLiqTokenReceived;
        /// @notice Snapshot creation timestamp (seconds since unix epoch).
        /// @dev Used to validate freshness of snapshots on the parent pool.
        uint32 timestamp;
    }

    error DepositQueueIsFull();
    error WithdrawalQueueIsFull();
    error QueuesAreNotFull();
    error LiquidityCapReached(uint256 liqCapAmount);
    error ChildPoolSnapshotsAreNotReady();
    error InvalidScoreWeights();
    error InvalidLurScoreSensitivity();
    error OnlySelf();

    event DepositQueued(bytes32 indexed id, address lp, uint256 amount);
    event DepositProcessed(
        bytes32 indexed id,
        address lp,
        uint256 liqTokenAmountWithFee,
        uint256 lpTokenAmount
    );
    event WithdrawalQueued(bytes32 indexed withdrawId, address lp, uint256 lpTokenAmount);
    event WithdrawalProcessed(
        bytes32 indexed id,
        address lp,
        uint256 lpTokenAmount,
        uint256 liqTokenAmount
    );
    event WithdrawalCompleted(bytes32 indexed id, uint256 liqTokenAmountReceivedWithFee);
    event WithdrawalFailed(address lp, uint256 liqTokenAmountToWithdraw);
}
