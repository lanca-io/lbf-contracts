// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPoolBase} from "./interfaces/IPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Storage as s} from "./libraries/Storage.sol";

contract PoolBase is IPoolBase {
    using s for s.PoolBase;

    address internal immutable i_liquidityToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    address internal i_conceroRouter;
    uint24 internal i_chainSelector;
    uint8 private constant LP_TOKEN_DECIMALS = 16;
    uint32 private constant SECONDS_IN_DAY = 86400;

    constructor(
        address liquidityToken,
        address conceroRouter,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) {
        i_liquidityToken = liquidityToken;

        i_liquidityTokenDecimals = liquidityTokenDecimals;
        i_conceroRouter = conceroRouter;
        i_chainSelector = chainSelector;
    }

    function getSupportedChainSelectors() public view returns (uint24[] memory) {
        return s.poolBase().supportedChainSelectors;
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

    function getYesterdayFlow() public view returns (LiqTokenAmountFlow memory) {
        return s.poolBase().flowByDay[getYesterdayStartTimestamp()];
    }

    function getTodayStartTimestamp() public view returns (uint32) {
        return uint32(block.timestamp) / SECONDS_IN_DAY;
    }

    function getYesterdayStartTimestamp() public view returns (uint32) {
        return getTodayStartTimestamp() - 1;
    }

    // TODO: move it to rebalancer module
    function getSurplus() public view returns (uint256) {
        uint256 activeBalance = getActiveBalance();
        uint256 tagetBalance = getTargetBalance();

        if (activeBalance <= tagetBalance) return 0;
        return activeBalance - tagetBalance;
    }

    function _setTargetBalance(uint256 updatedTargetBalance) internal {
        s.poolBase().targetBalance = updatedTargetBalance;
    }

    function _postInflow(uint256 inflowLiqTokenAmount) internal virtual {
        _incrementLiqInflow(inflowLiqTokenAmount);
    }

    function _postOutflow(uint256 outflowLiqTokenAmount) internal {
        _incrementLiqOutflow(outflowLiqTokenAmount);
    }

    function _incrementLiqInflow(uint256 inflowAmount) internal {
        s.poolBase().flowByDay[getTodayStartTimestamp()].inflow += inflowAmount;
    }

    function _incrementLiqOutflow(uint256 outflowAmount) internal {
        s.poolBase().flowByDay[getTodayStartTimestamp()].outflow += outflowAmount;
    }
}
