// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICommonErrors {
    error UnauthorizedSender(address caller, address expected);
    error InvalidAmount();
    error InvalidDstChainSelector(uint24 dstChainSelector);
    error InvalidChainSelector();
    error AddressShouldNotBeZero();
    error AmountIsZero();
    error DepositAmountIsTooLow(uint256 depositAmount, uint256 minDepositAmount);
    error WithdrawalAmountIsTooLow(uint256 withdrawalAmount, uint256 minWithdrawalAmount);
    error FunctionNotImplemented();
    error MinDepositAmountNotSet();
    error MinWithdrawalAmountNotSet();
}
