// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICommonErrors {
    error UnauthorizedCaller(address caller, address expected);
    error UnauthorizedSender(address caller, address expected);
    error InvalidAmount();
    error InvalidFeeAmount();
    error InvalidDstChainSelector(uint24 dstChainSelector);
    error InvalidChainSelector();
    error AddressShouldNotBeZero();
    error AmountIsZero();
    error LengthMismatch();
    error EmptyArray();
    error AddressIsZero();
}
