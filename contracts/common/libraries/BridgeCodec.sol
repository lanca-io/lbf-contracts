// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IParentPool} from "../../ParentPool/interfaces/IParentPool.sol";
import {IBase} from "../../Base/interfaces/IBase.sol";

library BridgeCodec {
    error PayloadToBig();
    error DstChainDataToBig();

    uint8 internal constant VERSION = 1;

    uint8 internal constant BYTES32_LENGTH_BYTES = 32;
    uint8 internal constant UINT24_LENGTH_BYTES = 3;
    uint8 internal constant UINT32_LENGTH_BYTES = 4;

    uint8 internal constant TYPE_OFFSET = 1;
    uint8 internal constant SENDER_OFFSET = 2;
    uint8 internal constant AMOUNT_OFFSET = SENDER_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant DST_CHAIN_DATA_OFFSET = AMOUNT_OFFSET + BYTES32_LENGTH_BYTES;

    uint8 internal constant ACTIVE_BALANCE_OFFSET = 2;
    uint8 internal constant INFLOW_FLOW_OFFSET = ACTIVE_BALANCE_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant OUTFLOW_FLOW_OFFSET = INFLOW_FLOW_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant IOU_TOTAL_SENT_OFFSET = OUTFLOW_FLOW_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant IOU_TOTAL_RECEIVED_OFFSET =
        IOU_TOTAL_SENT_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant IOU_TOTAL_SUPPLY = IOU_TOTAL_RECEIVED_OFFSET + BYTES32_LENGTH_BYTES;
    uint8 internal constant TIMESTAMP_OFFSET = IOU_TOTAL_SUPPLY + BYTES32_LENGTH_BYTES;
    uint8 internal constant TOTAL_LIQ_SENT_OFFSET = TIMESTAMP_OFFSET + UINT32_LENGTH_BYTES;
    uint8 internal constant TOTAL_LIQ_RECEIVED_OFFSET =
        TOTAL_LIQ_SENT_OFFSET + BYTES32_LENGTH_BYTES;

    function toAddress(bytes32 addr) internal pure returns (address) {
        return address(bytes20(addr));
    }

    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(bytes20(addr));
    }

    function getMessageType(bytes calldata data) internal pure returns (IBase.ConceroMessageType) {
        return IBase.ConceroMessageType(uint8(bytes1(data[:TYPE_OFFSET])));
    }

    function encodeBridgeData(
        address sender,
        uint256 amount,
        bytes memory dstChainData,
        bytes memory payload
    ) internal pure returns (bytes memory) {
        require(payload.length <= type(uint24).max, PayloadToBig());
        require(dstChainData.length <= type(uint24).max, DstChainDataToBig());

        return
            abi.encodePacked(
                IBase.ConceroMessageType.BRIDGE,
                VERSION,
                toBytes32(sender),
                amount,
                uint24(dstChainData.length),
                dstChainData,
                uint24(payload.length),
                payload
            );
    }

    function encodeBridgeIouData(
        bytes32 receiver,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(IBase.ConceroMessageType.BRIDGE_IOU, VERSION, receiver, amount);
    }

    function encodeChildPoolSnapshotData(
        uint256 activeBalance,
        uint256 inflow,
        uint256 outflow,
        uint256 iouTotalSent,
        uint256 iouTotalReceived,
        uint256 iouTotalSupply,
        uint32 timestamp,
        uint256 totalLiquidityTokenSent,
        uint256 totalLiquidityTokenReceived
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
                totalLiquidityTokenReceived
            );
    }

    function encodeUpdateTargetBalanceData(
        uint256 newTargetBalance
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                IBase.ConceroMessageType.UPDATE_TARGET_BALANCE,
                VERSION,
                newTargetBalance
            );
    }

    // DECODERS

    function decodeBridgeData(
        bytes calldata data
    ) internal pure returns (bytes32, uint256, bytes calldata, bytes memory) {
        uint24 dstChainDataLength = uint24(
            bytes3(data[DST_CHAIN_DATA_OFFSET:DST_CHAIN_DATA_OFFSET + UINT24_LENGTH_BYTES])
        );
        uint24 dstChainDataEnd = DST_CHAIN_DATA_OFFSET + dstChainDataLength + UINT24_LENGTH_BYTES;

        return (
            bytes32(data[SENDER_OFFSET:SENDER_OFFSET + BYTES32_LENGTH_BYTES]),
            uint256(bytes32(data[AMOUNT_OFFSET:AMOUNT_OFFSET + BYTES32_LENGTH_BYTES])),
            data[DST_CHAIN_DATA_OFFSET + UINT24_LENGTH_BYTES:dstChainDataEnd],
            data[dstChainDataEnd + UINT24_LENGTH_BYTES:]
        );
    }

    function decodeBridgeIouData(bytes calldata data) internal pure returns (bytes32, uint256) {
        return (
            bytes32(data[SENDER_OFFSET:SENDER_OFFSET + BYTES32_LENGTH_BYTES]),
            uint256(bytes32(data[AMOUNT_OFFSET:AMOUNT_OFFSET + BYTES32_LENGTH_BYTES]))
        );
    }

    function decodeChildPoolSnapshot(
        bytes calldata data
    ) internal pure returns (IParentPool.ChildPoolSnapshot memory) {
        return
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
                totalLiqTokenSent: uint256(
                    bytes32(data[TOTAL_LIQ_SENT_OFFSET:TOTAL_LIQ_RECEIVED_OFFSET])
                ),
                totalLiqTokenReceived: uint256(bytes32(data[TOTAL_LIQ_RECEIVED_OFFSET:])),
                timestamp: uint32(bytes4(data[TIMESTAMP_OFFSET:TOTAL_LIQ_SENT_OFFSET]))
            });
    }

    function decodeUpdateTargetBalanceData(bytes calldata data) internal pure returns (uint256) {
        return uint256(bytes32(data[SENDER_OFFSET:]));
    }
}
