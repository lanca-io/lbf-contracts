// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KeeperChildPoolWrapper
 * @dev Simplified mock contract for testing keeper functionality
 * Only exposes the sendSnapshotToParentPool function without inheritance complexity
 */
contract KeeperChildPoolWrapper {
    event SnapshotSent();

    /**
     * @dev Mock function to simulate sending snapshot to parent pool
     * This is a simple mock that just emits an event for testing purposes
     */
    function sendSnapshotToParentPool() external {
        emit SnapshotSent();
    }
}
