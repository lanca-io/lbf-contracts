// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LPToken} from "../ParentPool/LPToken.sol";
import {Storage as s} from "./libraries/Storage.sol";

contract PoolBase {
    using s for s.PoolBase;

    address internal immutable i_liquidityToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    LPToken internal immutable i_lpToken;
    uint8 internal constant LP_TOKEN_DECIMALS = 16;

    constructor(address liquidityToken, address lpToken, uint8 liquidityTokenDecimals) {
        i_liquidityToken = liquidityToken;
        i_lpToken = LPToken(lpToken);
        i_liquidityTokenDecimals = liquidityTokenDecimals;
    }

    function getLiquidityToken() public view returns (address) {
        return i_liquidityToken;
    }

    function getLpToken() public view returns (address) {
        return address(i_lpToken);
    }

    function getActiveBalance() public view virtual returns (uint256) {
        // TODO: deduct the rebalancing fee in the future
        return IERC20(i_liquidityToken).balanceOf(address(this));
    }

    function toLpTokenDecimals(uint256 liquidityTokenAmount) public view returns (uint256) {
        if (LP_TOKEN_DECIMALS == i_liquidityTokenDecimals) return liquidityTokenAmount;

        return (liquidityTokenAmount * LP_TOKEN_DECIMALS) / i_liquidityTokenDecimals;
    }

    function toLiqTokenDecimals(uint256 lpTokenAmount) public view returns (uint256) {
        if (LP_TOKEN_DECIMALS == i_liquidityTokenDecimals) return lpTokenAmount;

        return (lpTokenAmount * i_liquidityTokenDecimals) / LP_TOKEN_DECIMALS;
    }

    function getTargetBalance() public view returns (uint256) {
        return s.poolBase().targetBalance;
    }

    function _setTargetBalance(uint256 updatedTargetBalance) internal {
        s.poolBase().targetBalance = updatedTargetBalance;
    }
}
