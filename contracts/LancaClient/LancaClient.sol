// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ILancaClient} from "./interfaces/ILancaClient.sol";

/// @title LancaClient
/// @notice Base contract for applications that want to receive bridged liquidity from a Lanca pool.
/// @dev
/// - Implements the {ILancaClient} interface and ERC-165 introspection.
/// - Enforces that only a preconfigured Lanca pool contract can call `lancaReceive`.
/// - Contracts integrating with Lanca should inherit from this and implement `_lancaReceive`.
abstract contract LancaClient is ILancaClient, ERC165 {
    /// @notice Thrown when an invalid Lanca pool address is used in the constructor
    ///         or when a non-pool contract calls `lancaReceive`.
    error InvalidLancaPool();

    /// @notice Address of the Lanca pool that is allowed to invoke `lancaReceive`.
    /// @dev
    /// - Set once in the constructor and immutable afterwards.
    /// - Used as an authorization check for inbound bridge callbacks.
    address internal immutable i_lancaPool;

    /// @notice Initializes the Lanca client with the trusted Lanca pool address.
    /// @dev
    /// - Reverts if `lancaPool` is the zero address.
    /// - The provided `lancaPool` will be the only address allowed to call `lancaReceive`.
    /// @param lancaPool Address of the Lanca pool contract on this chain.
    constructor(address lancaPool) {
        require(lancaPool != address(0), InvalidLancaPool());
        i_lancaPool = lancaPool;
    }

    /// @notice ERC-165 interface support check.
    /// @dev
    /// - Returns true for:
    ///   * `ILancaClient` interface ID
    ///   * Any interface supported by the parent {ERC165}.
    /// @param interfaceId The interface identifier, as specified in ERC-165.
    /// @return True if this contract implements `interfaceId`, false otherwise.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(ILancaClient).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Entry point called by the Lanca pool when a bridge transfer is delivered.
    /// @dev
    /// - External and callable only by `i_lancaPool`.
    /// - Performs a strict sender check and forwards the call to the internal hook `_lancaReceive`.
    /// @param id Unique message/bridge identifier (from the Lanca / Concero layer).
    /// @param srcChainSelector Selector of the source chain from which funds were bridged.
    /// @param sender Address of the sender on the source chain encoded as `bytes32`.
    /// @param amount Amount of liquidity tokens delivered to this client.
    /// @param data Optional arbitrary payload forwarded from the source chain.
    function lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        bytes32 sender,
        uint256 amount,
        bytes calldata data
    ) external {
        require(msg.sender == i_lancaPool, InvalidLancaPool());
        _lancaReceive(id, srcChainSelector, sender, amount, data);
    }

    /// @notice Internal hook to handle an incoming Lanca bridge transfer.
    /// @dev
    /// - Must be implemented by inheriting contracts.
    /// - At this point:
    ///   * Authorization by the Lanca pool has already been checked.
    ///   * `amount` has been transferred to this contract by the pool.
    /// - Typical responsibilities:
    ///   * updating internal accounting,
    ///   * executing application-specific logic (e.g. deposit, position top-up),
    ///   * validating and using `data` as needed.
    /// @param id Unique message/bridge identifier.
    /// @param srcChainSelector Selector of the source chain.
    /// @param sender Sender address on the source chain encoded as `bytes32`.
    /// @param amount Amount of liquidity tokens received.
    /// @param data Optional payload provided by the sender on the source chain.
    function _lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        bytes32 sender,
        uint256 amount,
        bytes calldata data
    ) internal virtual;
}
