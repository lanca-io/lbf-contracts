// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IRebalancer
/// @notice Interface for cross-chain liquidity rebalancing using IOU tokens.
/// @dev
/// - Rebalancer logic lives on top of a Lanca pool and IOU token:
///   * `fillDeficit` — adds liquidity to the pool and mints IOU to the caller.
///   * `takeSurplus` — burns IOU and releases surplus liquidity to the caller.
///   * `bridgeIOU` — bridges IOU to another chain via Concero.
interface IRebalancer {
    event DeficitFilled(address indexed rebalancer, uint256 liqTokenAmount);
    event SurplusTaken(address indexed rebalancer, uint256 liqTokenAmount, uint256 iouTokenAmount);
    event IOUBridged(
        bytes32 indexed messageId,
        address sender,
        uint24 dstChainSelector,
        uint256 amount
    );
    event IOUReceived(
        bytes32 indexed messageId,
        address receiver,
        uint24 srcChainSelector,
        uint256 amount
    );

    error AmountExceedsDeficit(uint256 expected, uint256 received);
    error AmountExceedsSurplus(uint256 expected, uint256 received);
    error InvalidDestinationChain(uint24 chainSelector);

    /**
     * @notice Fills the pool deficit by supplying underlying liquidity tokens.
     * @dev
     * - Implementations are expected to:
     *   * check that `amount > 0`,
     *   * ensure `amount <= current deficit`,
     *   * transfer `amount` of liquidity tokens from `msg.sender` to the pool,
     *   * mint IOU tokens to `msg.sender` (usually 1:1 w.r.t. pool token),
     *   * optionally trigger post-inflow rebalancing logic.
     * - Emits:
     *   * {DeficitFilled}
     * @param amount Amount of liquidity tokens that the caller provides to reduce the deficit.
     */
    function fillDeficit(uint256 amount) external;

    /**
     * @notice Redeems IOU tokens against the pool surplus and receives underlying liquidity.
     * @dev
     * - Implementations are expected to:
     *   * check that `iouAmount > 0`,
     *   * ensure `iouAmount <= current surplus`,
     *   * burn `iouAmount` IOU tokens from `msg.sender`,
     *   * transfer corresponding liquidity tokens to `msg.sender`, minus/plus any configured fees,
     *   * update internal accounting for rebalancing fees.
     * - Emits:
     *   * {SurplusTaken}
     * @param iouAmount Amount of IOU tokens to burn in exchange for liquidity.
     * @return amount Amount of liquidity tokens transferred to the caller.
     */
    function takeSurplus(uint256 iouAmount) external returns (uint256 amount);

    /**
     * @notice Returns the address of the IOU token contract used by the rebalancer.
     * @dev IOU tokens represent claims on shared pool liquidity and are minted/burned
     *      during deficit-filling and surplus-taking operations.
     * @return iouToken Address of the IOU token.
     */
    function getIOUToken() external view returns (address iouToken);

    /**
     * @notice Bridges IOU tokens from the current chain to a destination chain.
     * @dev
     * - Implementations are expected to:
     *   * validate `receiver` and `dstChainSelector`,
     *   * burn `iouTokenAmount` IOU tokens from `msg.sender`,
     *   * construct and send a Concero message with a `BRIDGE_IOU` payload,
     *   * increment internal accounting for `totalIouSent`.
     * - The caller must supply enough `msg.value` to cover native cross-chain fees.
     *   Use {getBridgeIouNativeFee} to estimate required value.
     * - Emits:
     *   * {IOUBridged}
     * @param receiver Address (encoded as bytes32) that will receive IOU tokens on the destination chain.
     * @param dstChainSelector Destination chain selector where IOU tokens will be minted.
     * @param iouTokenAmount Amount of IOU tokens to bridge.
     * @return messageId Concero cross-chain message identifier associated with this bridge.
     */
    function bridgeIOU(
        bytes32 receiver,
        uint24 dstChainSelector,
        uint256 iouTokenAmount
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Returns the estimated native fee for bridging IOU tokens to a specific chain.
     * @dev
     * - Intended for frontends/integrators to pre-calculate `msg.value` for {bridgeIOU}.
     * - Implementations usually:
     *   * construct a sample `MessageRequest`,
     *   * call `IConceroRouter.getMessageFee` for that request.
     * @param dstChainSelector Destination chain selector for the IOU bridge.
     * @return fee Estimated fee in native tokens required to cover relayer + validator costs.
     */
    function getBridgeIouNativeFee(uint24 dstChainSelector) external view returns (uint256 fee);
}
