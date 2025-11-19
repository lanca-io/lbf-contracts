// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ILancaBridge {
    event BridgeSent(
        bytes32 indexed messageId,
        uint24 dstChainSelector,
        bytes dstChainData,
        address tokenSender,
        uint256 tokenAmountBeforeFee
    );
    event BridgeDelivered(bytes32 indexed messageId, uint256 tokenAmountAfterFee);
    event SrcBridgeReorged(uint24 indexed sourceChainSelector, uint256 oldAmount);

    error InvalidDstChainSelector(uint24 dstChainSelector);
    error InvalidDstGasLimitOrCallData();
    error InvalidConceroMessage();

    function bridge(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external payable returns (bytes32 messageId);

    function getBridgeNativeFee(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external view returns (uint256);
}
