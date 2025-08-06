// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ParentPool} from "../ParentPool/ParentPool.sol";
import {LPToken} from "../ParentPool/LPToken.sol";
import {IParentPool} from "../ParentPool/interfaces/IParentPool.sol";
import {Storage as s} from "../PoolBase/libraries/Storage.sol";
import {Storage as pps} from "../ParentPool/libraries/Storage.sol";

contract ParentPoolWrapper is ParentPool {
    using s for s.PoolBase;
    using s for pps.ParentPool;

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

    // Exposing internal functions for testing:
    function setTargetBalance(uint256 newTargetBalance) external {
        s.poolBase().targetBalance = newTargetBalance;
    }

    function calculateNewTargetBalances(
        uint256 totalLbfBalance
    ) external returns (uint24[] memory, uint256[] memory) {
        return _calculateNewTargetBalances(totalLbfBalance);
    }

    function calculateLhsScore(
        LiqTokenDailyFlow memory flow,
        uint256 targetBalance
    ) external returns (uint8) {
        return _calculateLhsScore(flow, targetBalance);
    }

    function calculateParentPoolTargetBalanceWeight() external returns (uint256) {
        return _calculateParentPoolTargetBalanceWeight();
    }

    function updateChildPoolTargetBalance(
        uint24 dstChainSelector,
        uint256 newTargetBalance
    ) external {
        _updateChildPoolTargetBalance(dstChainSelector, newTargetBalance);
    }

    function postInflowRebalance(uint256 inflowLiqTokenAmount) external {
        _postInflowRebalance(inflowLiqTokenAmount);
    }

    function processDepositsQueue(uint256 totalChildPoolsActiveBalance) external returns (uint256) {
        return _processDepositsQueue(totalChildPoolsActiveBalance);
    }

    function processWithdrawalsQueue(
        uint256 totalChildPoolsActiveBalance
    ) external returns (uint256) {
        return _processWithdrawalsQueue(totalChildPoolsActiveBalance);
    }

    function getChildPoolSubmission(
        uint24 dstChainSelector
    ) external view returns (IParentPool.SnapshotSubmission memory) {
        return pps.parentPool().childPoolsSubmissions[dstChainSelector];
    }

    function exposed_setDstPool(uint24 chainSelector, address dstPool) public {
        s.poolBase().dstPools[chainSelector] = dstPool;
    }

    // Keeper-specific setters for testing - using exact same storage as ParentPool
    function setQueuesFull(bool full) external {
        // Set queue lengths to target lengths to simulate full queues
        pps.parentPool().targetDepositQueueLength = 1;
        pps.parentPool().targetWithdrawalQueueLength = 1;

        // Add dummy queue entries to make queues appear full
        if (full) {
            bytes32 dummyDepositId = keccak256(abi.encodePacked(block.timestamp, "deposit"));
            bytes32 dummyWithdrawalId = keccak256(abi.encodePacked(block.timestamp, "withdrawal"));

            // Add to queue IDs to simulate full queues
            pps.parentPool().depositsQueueIds.push(dummyDepositId);
            pps.parentPool().withdrawalsQueueIds.push(dummyWithdrawalId);
        }
    }

    function setReadyToTriggerDepositWithdrawProcess(bool ready) external {
        // Set queue states to make trigger ready
        this.setQueuesFull(ready);

        // Ensure we have sufficient data for snapshots
        if (ready) {
            pps.parentPool().totalDepositAmountInQueue = 1000;
        }
    }

    function setReadyToProcessPendingWithdrawals(bool ready) external {
        // Set up pending withdrawals to process
        if (ready) {
            pps.parentPool().remainingWithdrawalAmount = 0;
            pps.parentPool().totalWithdrawalAmountLocked = 1000;

            // Add a dummy pending withdrawal
            bytes32 withdrawalId = keccak256(abi.encodePacked(block.timestamp, "pending"));
            pps.parentPool().pendingWithdrawalIds.push(withdrawalId);

            IParentPool.PendingWithdrawal memory withdrawal = IParentPool.PendingWithdrawal({
                lp: address(0x1111111111111111111111111111111111111111),
                lpTokenAmountToWithdraw: 100,
                liqTokenAmountToWithdraw: 100
            });
            pps.parentPool().pendingWithdrawals[withdrawalId] = withdrawal;
        }
    }
}
