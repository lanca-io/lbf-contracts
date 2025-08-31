// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    ConceroTypes,
    IConceroRouter
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {LancaBridge} from "../LancaBridge/LancaBridge.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {Base} from "../Base/Base.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IParentPool} from "../ParentPool/interfaces/IParentPool.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as pbs} from "../Base/libraries/Storage.sol";

contract ChildPool is Rebalancer, LancaBridge {
    using s for s.ChildPool;
    using rs for rs.Rebalancer;
    using pbs for pbs.Base;

    uint32 internal constant SEND_SNAPSHOT_MESSAGE_GAS_LIMIT = 100_000;
    uint24 internal immutable i_parentPoolChainSelector;

    constructor(
        address conceroRouter,
        address iouToken,
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector,
        uint24 parentPoolChainSelector
    )
        Base(liquidityToken, conceroRouter, iouToken, liquidityTokenDecimals, chainSelector)
        Rebalancer()
        LancaBridge()
    {
        i_parentPoolChainSelector = parentPoolChainSelector;
    }

    function sendSnapshotToParentPool() external payable onlyLancaKeeper {
        pbs.Base storage s_base = pbs.base();

        IParentPool.ChildPoolSnapshot memory snapshot = IParentPool.ChildPoolSnapshot({
            balance: getActiveBalance(),
            dailyFlow: getYesterdayFlow(),
            iouTotalSent: rs.rebalancer().totalIouSent,
            iouTotalReceived: rs.rebalancer().totalIouReceived,
            iouTotalSupply: i_iouToken.totalSupply(),
            timestamp: uint32(block.timestamp),
            totalLiqTokenReceived: s_base.totalLiqTokenSent,
            totalLiqTokenSent: s_base.totalLiqTokenReceived
        });

        address parentPool = s_base.dstPools[i_parentPoolChainSelector];
        require(
            parentPool != address(0),
            ICommonErrors.InvalidDstChainSelector(i_parentPoolChainSelector)
        );

        ConceroTypes.EvmDstChainData memory dstChainData = ConceroTypes.EvmDstChainData({
            gasLimit: SEND_SNAPSHOT_MESSAGE_GAS_LIMIT,
            receiver: parentPool
        });

        uint256 messageFee = IConceroRouter(i_conceroRouter).getMessageFee(
            i_parentPoolChainSelector,
            false,
            address(0),
            dstChainData
        );

        bytes memory messagePayload = abi.encode(
            ConceroMessageType.SEND_SNAPSHOT,
            abi.encode(snapshot)
        );

        IConceroRouter(i_conceroRouter).conceroSend{value: messageFee}(
            i_parentPoolChainSelector,
            false,
            address(0),
            dstChainData,
            messagePayload
        );
    }

    function _handleConceroReceiveUpdateTargetBalance(bytes memory messageData) internal override {
        uint256 targetBalance = abi.decode(messageData, (uint256));
        pbs.base().targetBalance = targetBalance;
    }

    function _handleConceroReceiveSnapshot(bytes32, uint24, bytes memory) internal pure override {
        revert ICommonErrors.FunctionNotImplemented();
    }
}
