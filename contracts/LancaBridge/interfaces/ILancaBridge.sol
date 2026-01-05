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
    event HookCallFailed(bytes32 indexed messageId, address indexed tokenReceiver, bytes reason);

    error InvalidDstChainSelector(uint24 dstChainSelector);
    error InvalidDstGasLimitOrCallData();
    error InvalidConceroMessage();

    /// @dev
    /// - Pulls `tokenAmount` of liquidity token from `msg.sender`.
    /// - Charges LP + bridge + rebalancer fees via `_chargeTotalLancaFee`.
    /// - Constructs and sends a Concero message to the destination pool:
    ///   * `dstChainSelector` selects the remote chain,
    ///   * `dstChainData` contains the remote receiver + optional hook gas,
    ///   * `payload` is optional user data passed to the receiver hook.
    /// - Updates:
    ///   * `totalLiqTokenSent`,
    ///   * daily inflow for `getTodayStartTimestamp()`.
    /// - Emits `BridgeSent`.
    /// - Reverts if:
    ///   * the destination pool for `dstChainSelector` is not configured.
    /// @param tokenAmount Amount of liquidity token to bridge (before fees), in local decimals.
    /// @param dstChainSelector Destination chain selector.
    /// @param dstChainData Encoded destination chain data (receiver + gas limit).
    /// @param payload Optional payload forwarded to the receiver hook on destination.
    /// @return messageId Unique Concero message identifier.
    function bridge(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external payable returns (bytes32 messageId);

    /// @notice Returns the native fee required to bridge tokens to another chain.
    /// @dev
    /// - Builds a `MessageRequest` similar to `bridge`, but:
    ///   * uses `tokenAmount = 1` (only structure matters for fee estimation),
    ///   * calls `getMessageFee` on the Concero router instead of `conceroSend`.
    /// - Uses:
    ///   * `dstChainSelector` as provided,
    ///   * `dstPools[dstChainSelector]` as destination pool (must be configured),
    ///   * `_buildDstChainData` for destination data,
    ///   * current caller (`msg.sender`) as encoded bridge `sender`.
    /// - Reverts if destination pool for `dstChainSelector` is not configured.
    /// @param tokenAmount Unused; included for interface compatibility.
    /// @param dstChainSelector Destination chain selector.
    /// @param dstChainData Encoded destination chain data (receiver/gas).
    /// @param payload Arbitrary user payload for the receiver hook.
    /// @return Native fee required to send this bridge message.
    function getBridgeNativeFee(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external view returns (uint256);
}
