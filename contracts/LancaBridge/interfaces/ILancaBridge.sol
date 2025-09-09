// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ILancaBridge {
    event BridgeSent(
        bytes32 indexed messageId,
        uint24 dstChainSelector,
        address tokenSender,
        address tokenReceiver,
        uint256 tokenAmountBeforeFee,
        uint256 dstGasLimit
    );
    event BridgeDelivered(bytes32 indexed messageId, uint256 tokenAmountAfterFee);
    event SrcBridgeReorged(uint24 indexed sourceChainSelector, uint256 oldAmount);

    error InvalidToken();
    error InvalidDstChainSelector();
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
        uint256 dstGasLimit
    ) external view returns (uint256);
}
