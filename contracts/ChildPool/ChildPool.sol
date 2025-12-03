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

/// @title Lanca Child Pool
/// @notice Child pool deployed on a satellite chain that reports its state to a parent pool.
/// @dev
/// - Inherits:
///   * `Rebalancer` – handles rebalancing-related state and logic,
///   * `LancaBridge` – handles liquidity bridging on the child chain.
/// - This contract:
///   * builds and sends periodic snapshots to the parent pool via Concero,
///   * exposes a helper for estimating the native fee for snapshot messages,
///   * updates its `targetBalance` based on messages received from the parent pool.
/// - Snapshot data includes:
///   * active liquidity,
///   * inflow/outflow for the previous day,
///   * IOU sent/received counters,
///   * IOU total supply,
///   * cumulative liquidity sent/received,
///   * token decimals.
contract ChildPool is Rebalancer, LancaBridge {
    using s for s.ChildPool;
    using rs for rs.Rebalancer;
    using pbs for pbs.Base;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;

    uint32 internal constant SEND_SNAPSHOT_MESSAGE_GAS_LIMIT = 150_000;
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

    /// @notice Sends a liquidity and flow snapshot from this child pool to the parent pool.
    /// @dev
    /// - Only callable by `LANCA_KEEPER`.
    /// - Steps:
    ///   1. Looks up the parent pool address in `dstPools[parentPoolChainSelector]`.
    ///   2. Builds a `MessageRequest` with:
    ///      * dst chain = parent pool chain,
    ///      * dst address = parent pool,
    ///      * validator/relayer libs from base storage,
    ///      * payload = encoded snapshot from `getEncodedSnapshot`.
    ///   3. Calls `conceroSend` on `i_conceroRouter`, forwarding `msg.value` as native fee.
    /// - Reverts if the parent pool is not configured.
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

    /// @notice Returns the native fee required to send a snapshot message to the parent pool.
    /// @dev
    /// - Builds the same `MessageRequest` as `sendSnapshotToParentPool`, but calls
    ///   `getMessageFee` instead of `conceroSend`.
    /// - Uses:
    ///   * `i_parentPoolChainSelector` as destination chain,
    ///   * `dstPools[parentPoolChainSelector]` as destination address,
    ///   * `SEND_SNAPSHOT_MESSAGE_GAS_LIMIT` as gas limit,
    ///   * `getEncodedSnapshot()` as payload.
    /// @return Fee amount in native token required for the snapshot message.
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

    /// @notice Encodes the current child pool snapshot into a Concero/bridge payload.
    /// @dev
    /// - Snapshot includes:
    ///   * active balance (`getActiveBalance()`),
    ///   * yesterday inflow/outflow (`getYesterdayFlow()`),
    ///   * total IOU sent/received (`totalIouSent` / `totalIouReceived`),
    ///   * IOU total supply,
    ///   * current timestamp,
    ///   * cumulative liquidity sent/received,
    ///   * liquidity token decimals.
    /// - Uses `BridgeCodec.encodeChildPoolSnapshotData` for compact encoding.
    /// @return Encoded snapshot payload ready to be used as message `payload`.
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

    /// @dev
    /// - Handles Concero `UPDATE_TARGET_BALANCE` messages.
    /// - Decodes `(amount, srcDecimals)` using `decodeUpdateTargetBalanceData`.
    /// - Converts `amount` from `srcDecimals` to local liquidity token decimals
    ///   via `_toLocalDecimals` and stores it as `targetBalance`.
    /// @param messageData Encoded target balance update payload.
    function _handleConceroReceiveUpdateTargetBalance(
        bytes calldata messageData
    ) internal override {
        (uint256 amount, uint8 srcDecimals) = messageData.decodeUpdateTargetBalanceData();
        pbs.base().targetBalance = _toLocalDecimals(amount, srcDecimals);
    }

    /// @dev
    /// - Child pools do not process snapshots coming from other chains.
    /// - This function always reverts with `FunctionNotImplemented`.
    function _handleConceroReceiveSnapshot(uint24, bytes calldata) internal pure override {
        revert ICommonErrors.FunctionNotImplemented();
    }
}
