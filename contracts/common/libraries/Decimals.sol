// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Decimals {
    function toDecimals(
        uint256 amount,
        uint8 decimalsFrom,
        uint8 decimalsTo
    ) internal pure returns (uint256) {
        if (decimalsFrom == decimalsTo) {
            return amount;
        }

        if (decimalsTo > decimalsFrom) {
            return amount * (10 ** (decimalsTo - decimalsFrom));
        }

        return amount / (10 ** (decimalsFrom - decimalsTo));
    }
}
