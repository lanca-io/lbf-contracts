// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ILancaBridge {
    event TokenSent(
        bytes32 indexed messageId,
        uint24 indexed dstChainSelector,
        address indexed token,
        address tokenSender,
        address tokenReceiver,
        uint256 tokenAmount,
        address dstPool
    );

    event BridgeDelivered(
        bytes32 indexed messageId,
        uint24 indexed sourceChainSelector,
        address indexed token,
        address tokenSender,
        address tokenReceiver,
        uint256 tokenAmount
    );

    event SrcBridgeReorged(
        uint256 oldAmount,
        uint256 newAmount,
        uint24 indexed sourceChainSelector
    );

    error InvalidToken();
    error InvalidDstPool();
    error InvalidDstGasLimitOrCallData();
    error InvalidConceroMessage();

    function bridge(
        address tokenReceiver,
        uint256 tokenAmount,
        uint24 dstChainSelector,
        uint256 dstGasLimit,
        bytes calldata dstCallData
    ) external payable returns (bytes32 messageId);

    function getBridgeNativeFee(
        uint24 dstChainSelector,
        address dstPool,
        uint256 dstGasLimit
    ) external view returns (uint256);
}
