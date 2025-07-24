// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICommonErrors {
    error UnauthorizedCaller(address caller, address expected);
    error InvalidDstChainSelector(uint24 dstChainSelector);
    error AmountIsToLow();
}
