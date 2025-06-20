// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract PoolBase {
    address internal immutable i_liquidityToken;

    constructor(address liquidityToken) {
        i_liquidityToken = liquidityToken;
    }

    function getLiquidityToken() public view returns (address) {
        return i_liquidityToken;
    }
}
