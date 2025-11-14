// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

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
    ) Base(liquidityToken, conceroRouter, iouToken, liquidityTokenDecimals, chainSelector) {
        i_parentPoolChainSelector = parentPoolChainSelector;
    }

    function sendSnapshotToParentPool() external payable onlyLancaKeeper {
        pbs.Base storage s_base = pbs.base();
        rs.Rebalancer storage s_rebalancer = rs.rebalancer();

        IParentPool.ChildPoolSnapshot memory snapshot = IParentPool.ChildPoolSnapshot({
            balance: getActiveBalance(),
            dailyFlow: getYesterdayFlow(),
            iouTotalSent: s_rebalancer.totalIouSent,
            iouTotalReceived: s_rebalancer.totalIouReceived,
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

        bytes memory messagePayload = abi.encode(
            ConceroMessageType.SEND_SNAPSHOT,
            abi.encode(snapshot)
        );

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: i_parentPoolChainSelector,
            srcBlockConfirmations: 0,
            feeToken: address(0),
            dstChainData: MessageCodec.encodeEvmDstChainData(
                parentPool,
                SEND_SNAPSHOT_MESSAGE_GAS_LIMIT
            ),
            validatorLibs: s_base.validatorLibs[i_parentPoolChainSelector],
            relayerLib: s_base.relayerLibs[i_parentPoolChainSelector],
            validatorConfigs: new bytes[](1), // TODO: or validatorLibs.length?
            relayerConfig: new bytes(0),
            payload: messagePayload
        });

        uint256 messageFee = IConceroRouter(i_conceroRouter).getMessageFee(messageRequest);

        IConceroRouter(i_conceroRouter).conceroSend{value: messageFee}(messageRequest);
    }

    function getSnapshotMessageFee() external view returns (uint256) {
        pbs.Base storage s_base = pbs.base();
        rs.Rebalancer storage s_rebalancer = rs.rebalancer();

        IParentPool.ChildPoolSnapshot memory snapshot = IParentPool.ChildPoolSnapshot({
            balance: getActiveBalance(),
            dailyFlow: getYesterdayFlow(),
            iouTotalSent: s_rebalancer.totalIouSent,
            iouTotalReceived: s_rebalancer.totalIouReceived,
            iouTotalSupply: i_iouToken.totalSupply(),
            timestamp: uint32(block.timestamp),
            totalLiqTokenReceived: s_base.totalLiqTokenSent,
            totalLiqTokenSent: s_base.totalLiqTokenReceived
        });

        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                IConceroRouter.MessageRequest({
                    dstChainSelector: i_parentPoolChainSelector,
                    srcBlockConfirmations: 0,
                    feeToken: address(0),
                    dstChainData: MessageCodec.encodeEvmDstChainData(
                        s_base.dstPools[i_parentPoolChainSelector],
                        SEND_SNAPSHOT_MESSAGE_GAS_LIMIT
                    ),
                    validatorLibs: s_base.validatorLibs[i_parentPoolChainSelector],
                    relayerLib: s_base.relayerLibs[i_parentPoolChainSelector],
                    validatorConfigs: new bytes[](1), // TODO: or validatorLibs.length?
                    relayerConfig: new bytes(0),
                    payload: abi.encode(ConceroMessageType.SEND_SNAPSHOT, abi.encode(snapshot))
                })
            );
    }

    function _handleConceroReceiveUpdateTargetBalance(bytes memory messageData) internal override {
        uint256 targetBalance = abi.decode(messageData, (uint256));
        pbs.base().targetBalance = targetBalance;
    }

    function _handleConceroReceiveSnapshot(uint24, bytes memory) internal pure override {
        revert ICommonErrors.FunctionNotImplemented();
    }
}
