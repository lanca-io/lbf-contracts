// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ILancaKeeper {
    /**
     * @notice Trigger deposit and withdraw processing in the ParentPool.
     * @dev This function is called by the Lanca keeper to process deposits and withdrawals.
     */
    function triggerDepositWithdrawProcess() external payable;
}
