// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title Decimals
/// @notice Utility library for converting token amounts between different decimal precisions.
/// @dev
/// - Designed for simple deterministic scaling between ERC-20 tokens with different `decimals()`.
/// - Uses integer arithmetic:
///   * When scaling up, multiplies by 10^(decimalsTo - decimalsFrom).
///   * When scaling down, divides by 10^(decimalsFrom - decimalsTo) and truncates remainder.
/// - Does not perform overflow checks on multiplication; callers should ensure that:
///   * `amount` and decimal differences are small enough to avoid overflow,
///   * or rely on upstream checks / realistic token ranges (e.g., 18–24 decimals).
library Decimals {
    /**
     * @notice Converts an `amount` from one decimal precision to another.
     * @dev
     * - If `decimalsFrom == decimalsTo`, returns `amount` unchanged.
     * - If `decimalsTo > decimalsFrom`, scales up by multiplying:
     *     `amount * 10^(decimalsTo - decimalsFrom)`.
     * - If `decimalsTo < decimalsFrom`, scales down by dividing:
     *     `amount / 10^(decimalsFrom - decimalsTo)`, truncating any remainder.
     *
     * @param amount       Value expressed in `decimalsFrom` precision.
     * @param decimalsFrom Source decimals (e.g., token A `decimals()`).
     * @param decimalsTo   Target decimals (e.g., token B `decimals()`).
     *
     * @return Scaled `amount` expressed in `decimalsTo` precision.
     */
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
