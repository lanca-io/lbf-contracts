// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "../Rebalancer/interfaces/IRebalancer.sol";
import {CommonTypes} from "../common/CommonTypes.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";
import {ConceroOwnable} from "../common/ConceroOwnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../Rebalancer/IOUToken.sol";
import {IPoolBase} from "./interfaces/IPoolBase.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";

abstract contract PoolBase is IPoolBase, ConceroClient, ConceroOwnable {
    using s for s.PoolBase;
    using s for rs.Rebalancer;

    error InvalidMessageType();

    uint32 private constant SECONDS_IN_DAY = 86400;

    address internal immutable i_liquidityToken;
    IOUToken internal immutable i_iouToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    uint24 internal i_chainSelector;

    constructor(
        address liquidityToken,
        address conceroRouter,
        address iouToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) ConceroClient(conceroRouter) {
        i_liquidityToken = liquidityToken;
        i_liquidityTokenDecimals = liquidityTokenDecimals;
        i_chainSelector = chainSelector;
        i_iouToken = IOUToken(iouToken);
    }

    function getActiveBalance() public view virtual returns (uint256) {
        return
            IERC20(i_liquidityToken).balanceOf(address(this)) -
            rs.rebalancer().totalRebalancingFee -
            s.poolBase().totalLancaFeeInLiqToken;
    }

    function getSurplus() public view returns (uint256) {
        uint256 activeBalance = getActiveBalance();
        uint256 tagetBalance = getTargetBalance();

        if (activeBalance <= tagetBalance) return 0;
        return activeBalance - tagetBalance;
    }

    function getDeficit() public view returns (uint256 deficit) {
        uint256 targetBalance = getTargetBalance();
        uint256 activeBalance = getActiveBalance();
        deficit = activeBalance >= targetBalance ? 0 : targetBalance - activeBalance;
    }

    function getPoolData() external view returns (uint256 deficit, uint256 surplus) {
        deficit = getDeficit();
        surplus = getSurplus();
    }

    function setDstPool(uint24 chainSelector, address dstPool) public virtual onlyOwner {
        require(chainSelector != i_chainSelector, ICommonErrors.InvalidChainSelector());
        require(dstPool != address(0), ICommonErrors.AddressShouldNotBeZero());

        s.poolBase().dstPools[chainSelector] = dstPool;
    }

    function _conceroReceive(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata sender,
        bytes calldata message
    ) internal override {
        address remoteSender = abi.decode(sender, (address));

        require(
            s.poolBase().dstPools[sourceChainSelector] == remoteSender,
            ICommonErrors.UnauthorizedSender(
                remoteSender,
                s.poolBase().dstPools[sourceChainSelector]
            )
        );

        (CommonTypes.MessageType messageType, bytes memory messageData) = abi.decode(
            message,
            (CommonTypes.MessageType, bytes)
        );

        if (messageType == CommonTypes.MessageType.BRIDGE_IOU) {
            _handleConceroReceiveBridgeIou(messageId, sourceChainSelector, message);
        } else {
            revert InvalidMessageType();
        }
    }

    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal virtual;

    function getTargetBalance() public view returns (uint256) {
        return s.poolBase().targetBalance;
    }

    function getYesterdayFlow() public view returns (LiqTokenDailyFlow memory) {
        return s.poolBase().flowByDay[getYesterdayStartTimestamp()];
    }

    function getTodayStartTimestamp() public view returns (uint32) {
        return uint32(block.timestamp) / SECONDS_IN_DAY;
    }

    function getYesterdayStartTimestamp() public view returns (uint32) {
        return getTodayStartTimestamp() - 1;
    }

    function _postInflow(uint256 inflowLiqTokenAmount) internal virtual {
        s.poolBase().flowByDay[getTodayStartTimestamp()].inflow += inflowLiqTokenAmount;
    }

    function _postOutflow(uint256 outflowLiqTokenAmount) internal {
        s.poolBase().flowByDay[getTodayStartTimestamp()].outflow += outflowLiqTokenAmount;
    }
}
