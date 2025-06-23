// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract PoolBase {
    address internal immutable i_liquidityToken;
    address internal immutable i_lpToken;

    constructor(address liquidityToken, address lpToken) {
        i_liquidityToken = liquidityToken;
        i_lpToken = lpToken;
    }

    function getLiquidityToken() public view returns (address) {
        return i_liquidityToken;
    }

    function getLpToken() public view returns (address) {
        return i_lpToken;
    }
}
