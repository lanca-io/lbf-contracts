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
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";

contract ChildPool is Rebalancer, LancaBridge {
    using s for s.ChildPool;
    using rs for rs.Rebalancer;
    using pbs for pbs.Base;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;

    uint32 internal constant SEND_SNAPSHOT_MESSAGE_GAS_LIMIT = 100_000;
    uint24 internal immutable i_parentPoolChainSelector;

    constructor(
        address conceroRouter,
        address iouToken,
        address liquidityToken,
        uint24 chainSelector,
        uint24 parentPoolChainSelector
    ) Base(liquidityToken, conceroRouter, iouToken, chainSelector) {
        i_parentPoolChainSelector = parentPoolChainSelector;
    }

    function sendSnapshotToParentPool() external payable onlyRole(LANCA_KEEPER) {
        pbs.Base storage s_base = pbs.base();

        bytes32 parentPool = s_base.dstPools[i_parentPoolChainSelector];
        require(
            parentPool != bytes32(0),
            ICommonErrors.InvalidDstChainSelector(i_parentPoolChainSelector)
        );

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: i_parentPoolChainSelector,
            srcBlockConfirmations: 0,
            feeToken: address(0),
            dstChainData: MessageCodec.encodeEvmDstChainData(
                address(bytes20(parentPool)),
                SEND_SNAPSHOT_MESSAGE_GAS_LIMIT
            ),
            validatorLibs: validatorLibs,
            relayerLib: s_base.relayerLib,
            validatorConfigs: new bytes[](1),
            relayerConfig: new bytes(0),
            payload: getEncodedSnapshot()
        });

        IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(messageRequest);
    }

    function getSnapshotMessageFee() external view returns (uint256) {
        pbs.Base storage s_base = pbs.base();

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                IConceroRouter.MessageRequest({
                    dstChainSelector: i_parentPoolChainSelector,
                    srcBlockConfirmations: 0,
                    feeToken: address(0),
                    dstChainData: MessageCodec.encodeEvmDstChainData(
                        s_base.dstPools[i_parentPoolChainSelector].toAddress(),
                        SEND_SNAPSHOT_MESSAGE_GAS_LIMIT
                    ),
                    validatorLibs: validatorLibs,
                    relayerLib: s_base.relayerLib,
                    validatorConfigs: new bytes[](1),
                    relayerConfig: new bytes(0),
                    payload: getEncodedSnapshot()
                })
            );
    }

    function getEncodedSnapshot() public view returns (bytes memory) {
        pbs.Base storage s_base = pbs.base();
        rs.Rebalancer storage s_rebalancer = rs.rebalancer();

        LiqTokenDailyFlow memory dailyFlow = getYesterdayFlow();

        return
            BridgeCodec.encodeChildPoolSnapshotData(
                getActiveBalance(),
                dailyFlow.inflow,
                dailyFlow.outflow,
                s_rebalancer.totalIouSent,
                s_rebalancer.totalIouReceived,
                i_iouToken.totalSupply(),
                uint32(block.timestamp),
                s_base.totalLiqTokenSent,
                s_base.totalLiqTokenReceived,
                i_liquidityTokenDecimals
            );
    }

    function _handleConceroReceiveUpdateTargetBalance(
        bytes calldata messageData
    ) internal override {
        (uint256 amount, uint8 srcDecimals) = messageData.decodeUpdateTargetBalanceData();
        pbs.base().targetBalance = _toLocalDecimals(amount, srcDecimals);
    }

    function _handleConceroReceiveSnapshot(uint24, bytes calldata) internal pure override {
        revert ICommonErrors.FunctionNotImplemented();
    }
}
