// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title KeeperParentPoolWrapper
 * @dev Simplified mock contract for testing keeper functionality
 * Exposes only the functions needed for keeper testing with simple state management
 */
contract KeeperParentPoolWrapper {
    // Simple state variables for keeper testing
    bool public s_areQueuesFull;
    bool public s_isReadyToTriggerDepositWithdrawProcess;
    bool public s_isReadyToProcessPendingWithdrawals;

    // Events for tracking keeper actions
    event DepositWithdrawTriggered();
    event PendingWithdrawalsProcessed();

    /**
     * @dev Returns whether queues are full
     */
    function areQueuesFull() public view returns (bool) {
        return s_areQueuesFull;
    }

    /**
     * @dev Returns whether ready to trigger deposit withdraw process
     */
    function isReadyToTriggerDepositWithdrawProcess() external view returns (bool) {
        return s_isReadyToTriggerDepositWithdrawProcess;
    }

    /**
     * @dev Triggers the deposit withdraw process
     * This is a mock that just emits an event
     */
    function triggerDepositWithdrawProcess() external {
        emit DepositWithdrawTriggered();
    }

    /**
     * @dev Returns whether ready to process pending withdrawals
     */
    function isReadyToProcessPendingWithdrawals() public view returns (bool) {
        return s_isReadyToProcessPendingWithdrawals;
    }

    /**
     * @dev Processes pending withdrawals
     * This is a mock that just emits an event
     */
    function processPendingWithdrawals() external {
        emit PendingWithdrawalsProcessed();
    }

    // Setter functions for test manipulation

    /**
     * @dev Sets whether queues are full
     * @param full Boolean indicating if queues are full
     */
    function setQueuesFull(bool full) external {
        s_areQueuesFull = full;
    }

    /**
     * @dev Sets readiness for deposit withdraw process
     * @param ready Boolean indicating if ready to trigger
     */
    function setReadyToTriggerDepositWithdrawProcess(bool ready) external {
        s_isReadyToTriggerDepositWithdrawProcess = ready;
    }

    /**
     * @dev Sets readiness for processing pending withdrawals
     * @param ready Boolean indicating if ready to process
     */
    function setReadyToProcessPendingWithdrawals(bool ready) external {
        s_isReadyToProcessPendingWithdrawals = ready;
    }
}
