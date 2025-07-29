// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPriceFeeds {
    function getNativeNativeRate(uint24 chainSelector) external view returns (uint256);
    function getNativeUsdRate() external view returns (uint256);
}
