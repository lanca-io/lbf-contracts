// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    ConceroTypes,
    IConceroRouter
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IParentPool} from "../ParentPool/interfaces/IParentPool.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as pbs} from "../PoolBase/libraries/Storage.sol";

contract ChildPool is Rebalancer {
    using s for s.ChildPool;
    using s for rs.Rebalancer;
    using pbs for pbs.PoolBase;

    uint32 internal constant SEND_SNAPSHOT_MESSAGE_GAS_LIMIT = 100_000;

    event SnapshotSent(
        bytes32 indexed messageId,
        uint24 indexed parentPoolChainSelector,
        IParentPool.SnapshotSubmission snapshot
    );

    constructor(
        address conceroRouter,
        address iouToken,
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    )
        PoolBase(liquidityToken, conceroRouter, iouToken, liquidityTokenDecimals, chainSelector)
        Rebalancer()
    {}

    function sendSnapshotToParentPool(
        uint24 parentPoolChainSelector
    ) external payable onlyLancaKeeper {
        IParentPool.SnapshotSubmission memory snapshot = IParentPool.SnapshotSubmission({
            balance: getActiveBalance(),
            dailyFlow: getYesterdayFlow(),
            iouTotalSent: rs.rebalancer().totalIouSent,
            iouTotalReceived: rs.rebalancer().totalIouReceived,
            iouTotalSupply: i_iouToken.totalSupply(),
            timestamp: uint32(block.timestamp)
        });

        address parentPool = pbs.poolBase().dstPools[parentPoolChainSelector];
        require(
            parentPool != address(0),
            ICommonErrors.InvalidDstChainSelector(parentPoolChainSelector)
        );

        ConceroTypes.EvmDstChainData memory dstChainData = ConceroTypes.EvmDstChainData({
            gasLimit: SEND_SNAPSHOT_MESSAGE_GAS_LIMIT,
            receiver: parentPool
        });

        uint256 messageFee = IConceroRouter(i_conceroRouter).getMessageFee(
            parentPoolChainSelector,
            false,
            address(0),
            dstChainData
        );

        bytes memory messagePayload = abi.encode(ConceroMessageType.SEND_SNAPSHOT, snapshot);

        bytes32 messageId = IConceroRouter(i_conceroRouter).conceroSend{value: messageFee}(
            parentPoolChainSelector,
            false,
            address(0),
            dstChainData,
            messagePayload
        );

        emit SnapshotSent(messageId, parentPoolChainSelector, snapshot);
    }

    function _handleConceroReceiveSnapshot(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal override {}
}
