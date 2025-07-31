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

    error OnlyAllowedTokens();
    error InvalidBridgeType();
    error InvalidDestinationPool();
}
