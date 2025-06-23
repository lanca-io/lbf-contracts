// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    function getActiveBalance() public view returns (uint256) {
        // TODO: deduct the rebalancing fee in the future
        return IERC20(i_liquidityToken).balanceOf(address(this));
    }
}
