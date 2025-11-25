// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICommonErrors {
    error UnauthorizedCaller(address caller, address expected);
    error UnauthorizedSender(address caller, address expected);
    error InvalidAmount();
    error InvalidDstChainSelector(uint24 dstChainSelector);
    error InvalidChainSelector();
    error AddressShouldNotBeZero();
    error AmountIsZero();
    error DepositAmountIsTooLow(uint256 depositAmount, uint64 minDepositAmount);
    error WithdrawalAmountIsTooLow(uint256 withdrawalAmount, uint64 minWithdrawalAmount);
    error FunctionNotImplemented();
    error MinDepositAmountNotSet();
    error MinWithdrawalAmountNotSet();
    error LengthMismatch();
}
