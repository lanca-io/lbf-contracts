// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IParentPool} from "../../ParentPool/interfaces/IParentPool.sol";
import {IBase} from "../../Base/interfaces/IBase.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title BridgeCodec
/// @notice Encoding and decoding helpers for Lanca cross-chain pool messages.
/// @dev
/// - Encodes payloads used by:
///   * LancaBridge (liquidity bridge messages),
///   * Rebalancer (IOU bridge messages),
///   * ParentPool / ChildPool (snapshot & target-balance update messages).
/// - Message layout is tightly packed and relies on byte offsets defined below.
/// - All decoders assume the layout produced by the corresponding encoders.
library BridgeCodec {
    using SafeCast for uint256;

    uint8 internal constant VERSION = 1;

    uint8 internal constant UINT8_LENGTH_BYTES = 1;
    uint8 internal constant UINT24_LENGTH_BYTES = 3;
    uint8 internal constant UINT32_LENGTH_BYTES = 4;
    uint8 internal constant BYTES32_LENGTH_BYTES = 32;

    // Layout (BRIDGE / BRIDGE_IOU / UPDATE_TARGET_BALANCE messages):
    //
    // 0:  [1]   messageType  (IBase.ConceroMessageType)
    // 1:  [1]   version
    // 2:  [32]  amount
    // 34: [1]   decimals
    // 35: [32]  sender/receiver (bytes32)  -- only for BRIDGE / BRIDGE_IOU
    // 67: [3]   dstChainData length        -- only for BRIDGE
    // ...       dstChainData bytes         -- only for BRIDGE
    // ...       [3] payload length         -- only for BRIDGE
    // ...       payload bytes              -- only for BRIDGE
    uint8 internal constant TYPE_OFFSET = 1;
    uint8 internal constant AMOUNT_OFFSET = 2;
    uint8 internal constant DECIMALS_OFFSET = AMOUNT_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant SENDER_OFFSET = DECIMALS_OFFSET + UINT8_LENGTH_BYTES;
    uint8 internal constant RECEIVER_OFFSET = SENDER_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant PAYLOAD_LENGTH_OFFSET = RECEIVER_OFFSET + BYTES32_LENGTH_BYTES;

    // Layout (SEND_SNAPSHOT messages):
    //
    // 0:  [1]   messageType
    // 1:  [1]   version
    // 2:  [32]  activeBalance
    // 34: [32]  dailyFlow.inflow
    // 66: [32]  dailyFlow.outflow
    // 98: [32]  iouTotalSent
    // 130:[32]  iouTotalReceived
    // 162:[32]  iouTotalSupply
    // 194:[4]   timestamp
    // 198:[32]  totalLiqTokenSent
    // 230:[32]  totalLiqTokenReceived
    // 262:[1]   decimals (snapshot token decimals)
    uint8 internal constant ACTIVE_BALANCE_OFFSET = 2;
    uint8 internal constant INFLOW_FLOW_OFFSET = ACTIVE_BALANCE_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant OUTFLOW_FLOW_OFFSET = INFLOW_FLOW_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant IOU_TOTAL_SENT_OFFSET = OUTFLOW_FLOW_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant IOU_TOTAL_RECEIVED_OFFSET =
        IOU_TOTAL_SENT_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant IOU_TOTAL_SUPPLY = IOU_TOTAL_RECEIVED_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant TIMESTAMP_OFFSET = IOU_TOTAL_SUPPLY + BYTES32_LENGTH_BYTES;
    uint16 internal constant TOTAL_LIQ_SENT_OFFSET = TIMESTAMP_OFFSET + UINT32_LENGTH_BYTES;
    uint16 internal constant TOTAL_LIQ_RECEIVED_OFFSET =
        TOTAL_LIQ_SENT_OFFSET + BYTES32_LENGTH_BYTES;
    uint16 internal constant SNAPSHOT_DECIMALS_OFFSET =
        TOTAL_LIQ_RECEIVED_OFFSET + BYTES32_LENGTH_BYTES;

    function toAddress(bytes32 addr) internal pure returns (address) {
        return address(bytes20(addr));
    }

    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(bytes20(addr));
    }

    function getMessageType(bytes calldata data) internal pure returns (IBase.ConceroMessageType) {
        return IBase.ConceroMessageType(uint8(bytes1(data[:TYPE_OFFSET])));
    }

    /// @notice Encodes a BRIDGE message payload for liquidity transfers.
    /// @dev Layout:
    /// - [0]   : messageType = ConceroMessageType.BRIDGE
    /// - [1]   : VERSION
    /// - [2..34)   : amount (uint256)
    /// - [34..35)  : decimals (uint8)
    /// - [35..67)  : sender as bytes32
    /// - [67..99)  : receiver as bytes32
    /// - [99..102) : payload length (uint24)
    /// - [102..]   : payload bytes
    /// @param sender Original sender address on the source chain.
    /// @param receiver Receiver address on the destination chain.
    /// @param amount Amount of tokens being bridged, in `decimals` units.
    /// @param decimals Decimals of the bridged token on the source chain.
    /// @param payload Optional hook payload to be forwarded to the destination receiver.
    /// @return Encoded BRIDGE message bytes.
    function encodeBridgeData(
        address sender,
        address receiver,
        uint256 amount,
        uint8 decimals,
        bytes memory payload
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                IBase.ConceroMessageType.BRIDGE,
                VERSION,
                amount,
                decimals,
                toBytes32(sender),
                toBytes32(receiver),
                payload.length.toUint24(),
                payload
            );
    }

    /// @notice Encodes a BRIDGE_IOU message payload for IOU transfers.
    /// @dev Layout:
    /// - [0]   : messageType = ConceroMessageType.BRIDGE_IOU
    /// - [1]   : VERSION
    /// - [2..34)   : amount (uint256)
    /// - [34..35)  : decimals (uint8)
    /// - [35..67)  : receiver (bytes32)
    /// @param receiver Receiver address on the destination chain, encoded as bytes32.
    /// @param amount Amount of IOU tokens being bridged.
    /// @param decimals Decimals of the liquidity/IOU token on the source chain.
    /// @return Encoded BRIDGE_IOU message bytes.
    function encodeBridgeIouData(
        bytes32 receiver,
        uint256 amount,
        uint8 decimals
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                IBase.ConceroMessageType.BRIDGE_IOU,
                VERSION,
                amount,
                decimals,
                receiver
            );
    }

    /// @notice Encodes a SEND_SNAPSHOT message payload for child pool state snapshots.
    /// @dev Layout:
    /// - [0]   : messageType = ConceroMessageType.SEND_SNAPSHOT
    /// - [1]   : VERSION
    /// - [2..34)   : activeBalance
    /// - [34..66)  : inflow (daily inflow)
    /// - [66..98)  : outflow (daily outflow)
    /// - [98..130) : iouTotalSent
    /// - [130..162): iouTotalReceived
    /// - [162..194): iouTotalSupply
    /// - [194..198): timestamp (uint32)
    /// - [198..230): totalLiquidityTokenSent
    /// - [230..262): totalLiquidityTokenReceived
    /// - [262..263): decimals (uint8, local liquidity token decimals on the child pool)
    /// @param activeBalance Current active pool balance on the child chain.
    /// @param inflow Liquidity inflow over the last day.
    /// @param outflow Liquidity outflow over the last day.
    /// @param iouTotalSent Total IOU amount sent out from this child pool.
    /// @param iouTotalReceived Total IOU amount received by this child pool.
    /// @param iouTotalSupply Current IOU total supply at the child pool.
    /// @param timestamp Snapshot timestamp (seconds since unix epoch).
    /// @param totalLiquidityTokenSent Total liquidity tokens sent out via bridges.
    /// @param totalLiquidityTokenReceived Total liquidity tokens received via bridges.
    /// @param decimals Local liquidity token decimals at the child pool (used for rescaling).
    /// @return Encoded SEND_SNAPSHOT message bytes.
    function encodeChildPoolSnapshotData(
        uint256 activeBalance,
        uint256 inflow,
        uint256 outflow,
        uint256 iouTotalSent,
        uint256 iouTotalReceived,
        uint256 iouTotalSupply,
        uint32 timestamp,
        uint256 totalLiquidityTokenSent,
        uint256 totalLiquidityTokenReceived,
        uint8 decimals
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                IBase.ConceroMessageType.SEND_SNAPSHOT,
                VERSION,
                activeBalance,
                inflow,
                outflow,
                iouTotalSent,
                iouTotalReceived,
                iouTotalSupply,
                timestamp,
                totalLiquidityTokenSent,
                totalLiquidityTokenReceived,
                decimals
            );
    }

    /// @notice Encodes an UPDATE_TARGET_BALANCE message payload.
    /// @dev Layout:
    /// - [0]   : messageType = ConceroMessageType.UPDATE_TARGET_BALANCE
    /// - [1]   : VERSION
    /// - [2..34)   : newTargetBalance (uint256)
    /// - [34..35)  : decimals (uint8)
    /// @param newTargetBalance New target balance expressed in `decimals` precision.
    /// @param decimals Decimals of the liquidity token on the sender chain.
    /// @return Encoded UPDATE_TARGET_BALANCE message bytes.
    function encodeUpdateTargetBalanceData(
        uint256 newTargetBalance,
        uint8 decimals
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                IBase.ConceroMessageType.UPDATE_TARGET_BALANCE,
                VERSION,
                newTargetBalance,
                decimals
            );
    }

    // DECODERS

    /// @notice Decodes a BRIDGE message payload encoded by {encodeBridgeData}.
    /// @dev Expects:
    /// - messageType = ConceroMessageType.BRIDGE
    /// - version = VERSION
    /// @param data Encoded BRIDGE message payload.
    /// @return amount Bridged token amount.
    /// @return decimals Token decimals on the source chain.
    /// @return sender Sender address encoded as bytes32 (use {toAddress} to decode).
    /// @return receiver Receiver address encoded as bytes32 (use {toAddress} to decode).
    /// @return payload Hook payload bytes to be forwarded to the destination (may be empty).
    function decodeBridgeData(
        bytes calldata data
    ) internal pure returns (uint256, uint8, bytes32, bytes32, bytes calldata) {
        return (
            uint256(bytes32(data[AMOUNT_OFFSET:DECIMALS_OFFSET])),
            uint8(bytes1(data[DECIMALS_OFFSET:SENDER_OFFSET])),
            bytes32(data[SENDER_OFFSET:RECEIVER_OFFSET]),
            bytes32(data[RECEIVER_OFFSET:PAYLOAD_LENGTH_OFFSET]),
            data[PAYLOAD_LENGTH_OFFSET + UINT24_LENGTH_BYTES:]
        );
    }

    /// @notice Decodes a BRIDGE_IOU message payload encoded by {encodeBridgeIouData}.
    /// @dev Expects:
    /// - messageType = ConceroMessageType.BRIDGE_IOU
    /// - version = VERSION
    /// @param data Encoded BRIDGE_IOU message payload.
    /// @return receiver Receiver encoded as bytes32 (use {toAddress} to decode).
    /// @return amount Amount of bridged IOU tokens.
    /// @return decimals IOU / liquidity token decimals on the source chain.
    function decodeBridgeIouData(
        bytes calldata data
    ) internal pure returns (bytes32, uint256, uint8) {
        return (
            bytes32(data[SENDER_OFFSET:SENDER_OFFSET + BYTES32_LENGTH_BYTES]),
            uint256(bytes32(data[AMOUNT_OFFSET:AMOUNT_OFFSET + BYTES32_LENGTH_BYTES])),
            uint8(bytes1(data[DECIMALS_OFFSET:DECIMALS_OFFSET + UINT8_LENGTH_BYTES]))
        );
    }

    /// @notice Decodes a SEND_SNAPSHOT message payload encoded by {encodeChildPoolSnapshotData}.
    /// @dev
    /// - All amounts in the returned snapshot are in the same decimal precision that was
    ///   used by the child pool when encoding (returned in `decimals`).
    /// - Callers are expected to rescale these values to their local precision if needed.
    /// @param data Encoded SEND_SNAPSHOT message payload.
    /// @return snapshot Decoded child pool snapshot struct.
    /// @return decimals Liquidity token decimals used on the child pool when encoding.
    function decodeChildPoolSnapshot(
        bytes calldata data
    ) internal pure returns (IParentPool.ChildPoolSnapshot memory, uint8 decimals) {
        return (
            IParentPool.ChildPoolSnapshot({
                balance: uint256(bytes32(data[ACTIVE_BALANCE_OFFSET:INFLOW_FLOW_OFFSET])),
                dailyFlow: IBase.LiqTokenDailyFlow({
                    inflow: uint256(bytes32(data[INFLOW_FLOW_OFFSET:OUTFLOW_FLOW_OFFSET])),
                    outflow: uint256(bytes32(data[OUTFLOW_FLOW_OFFSET:IOU_TOTAL_SENT_OFFSET]))
                }),
                iouTotalSent: uint256(
                    bytes32(data[IOU_TOTAL_SENT_OFFSET:IOU_TOTAL_RECEIVED_OFFSET])
                ),
                iouTotalReceived: uint256(
                    bytes32(data[IOU_TOTAL_RECEIVED_OFFSET:IOU_TOTAL_SUPPLY])
                ),
                iouTotalSupply: uint256(bytes32(data[IOU_TOTAL_SUPPLY:TIMESTAMP_OFFSET])),
                timestamp: uint32(bytes4(data[TIMESTAMP_OFFSET:TOTAL_LIQ_SENT_OFFSET])),
                totalLiqTokenSent: uint256(
                    bytes32(data[TOTAL_LIQ_SENT_OFFSET:TOTAL_LIQ_RECEIVED_OFFSET])
                ),
                totalLiqTokenReceived: uint256(
                    bytes32(data[TOTAL_LIQ_RECEIVED_OFFSET:SNAPSHOT_DECIMALS_OFFSET])
                )
            }),
            uint8(bytes1(data[SNAPSHOT_DECIMALS_OFFSET:]))
        );
    }

    /// @notice Decodes an UPDATE_TARGET_BALANCE message payload encoded by
    ///         {encodeUpdateTargetBalanceData}.
    /// @param data Encoded UPDATE_TARGET_BALANCE message payload.
    /// @return newTargetBalance New target balance, in `decimals` precision.
    /// @return decimals Liquidity token decimals on the sender chain.
    function decodeUpdateTargetBalanceData(
        bytes calldata data
    ) internal pure returns (uint256, uint8) {
        return (
            uint256(bytes32(data[AMOUNT_OFFSET:DECIMALS_OFFSET])),
            uint8(bytes1(data[DECIMALS_OFFSET:]))
        );
    }
}
