// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title ILancaClient
/// @notice Interface for contracts that want to receive funds via the Lanca bridge.
/// @dev
/// - Implementing contracts are expected to be called by a Lanca pool contract
///   when a cross-chain transfer is delivered.
/// - For a safe integration:
///   * You should restrict who is allowed to call `lancaReceive` (typically the pool),
///   * and implement your own application-specific logic inside the callback.
interface ILancaClient {
    /**
     * @notice Called by the Lanca pool when bridged liquidity is delivered to this contract.
     * @dev
     * - MUST be called only by a trusted Lanca pool contract (enforced on the client side).
     * - `amount` is already transferred to this contract by the time this function is called
     *   (depending on pool implementation).
     * - `sender` is the original sender on the source chain, encoded as `bytes32`
     *   and can be converted via `address(bytes20(sender))` or a dedicated helper.
     *
     * Typical usages:
     * - Depositing received funds into a strategy,
     * - Crediting user balances,
     * - Executing any custom cross-chain action specified in `payload`.
     *
     * @param id              Unique bridge/message identifier provided by the Lanca / Concero layer.
     * @param srcChainSelector Selector of the source chain where the bridge originated.
     * @param sender          Sender address on the source chain, encoded as `bytes32`.
     * @param amount          Amount of liquidity tokens delivered to this client.
     * @param payload         Arbitrary user-defined data forwarded from the source chain.
     */
    function lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        bytes32 sender,
        uint256 amount,
        bytes calldata payload
    ) external;
}
