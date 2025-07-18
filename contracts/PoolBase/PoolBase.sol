// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPoolBase} from "./interfaces/IPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LPToken} from "../ParentPool/LPToken.sol";
import {Storage as s} from "./libraries/Storage.sol";

contract PoolBase is IPoolBase {
    using s for s.PoolBase;

    address internal immutable i_liquidityToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    LPToken internal immutable i_lpToken;
    uint8 private constant LP_TOKEN_DECIMALS = 16;
    uint32 private constant SECONDS_IN_DAY = 86400;

    constructor(address liquidityToken, uint8 liquidityTokenDecimals) {
        i_liquidityToken = liquidityToken;
        i_liquidityTokenDecimals = liquidityTokenDecimals;
    }

    function getLiquidityToken() public view returns (address) {
        return i_liquidityToken;
    }

    function getLpToken() public view returns (address) {
        return address(i_lpToken);
    }

    function getActiveBalance() public virtual view returns (uint256) {
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

    function getYesterdayFlow() public view returns (LiqTokenAmountFlow memory) {
        return s.poolBase().flowByDay[getYesterdayStartTimestamp()];
    }

    function getTodayStartTimestamp() public view returns (uint32) {
        return uint32(block.timestamp) / SECONDS_IN_DAY;
    }

    function getYesterdayStartTimestamp() public view returns (uint32) {
        return getTodayStartTimestamp() - 1;
    }

    function _setTargetBalance(uint256 updatedTargetBalance) internal {
        s.poolBase().targetBalance = updatedTargetBalance;
    }

    function _postInflow(uint256 inflowLiqTokenAmount) internal {
        _incrementLiqInflow(inflowLiqTokenAmount);
    }

    function _postOutflow(uint256 outflowLiqTokenAmount) internal {
        _incrementLiqOutflow(outflowLiqTokenAmount);
    }

    function _incrementLiqInflow(uint256 inflowAmount) internal {
        s.poolBase().flowByDay[getTodayStartTimestamp()].inFlow += inflowAmount;
    }

    function _incrementLiqOutflow(uint256 outflowAmount) internal {
        s.poolBase().flowByDay[getTodayStartTimestamp()].outFlow += outflowAmount;
    }

    function getCurrentDeficit() public view returns (uint256 deficit) {
        uint256 targetBalance = getTargetBalance();
        uint256 activeBalance = getActiveBalance();
        deficit =  activeBalance >= targetBalance ? 0 : targetBalance - activeBalance;
    }

    function getCurrentSurplus() public view returns (uint256 surplus) {
        uint256 targetBalance = getTargetBalance();
        uint256 activeBalance = getActiveBalance();
        surplus = activeBalance <= targetBalance ? 0 : activeBalance - targetBalance;
    }
}
