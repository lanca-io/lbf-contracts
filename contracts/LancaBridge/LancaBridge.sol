// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Base} from "../Base/Base.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILancaBridge} from "./interfaces/ILancaBridge.sol";
import {ILancaClient} from "../LancaClient/interfaces/ILancaClient.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Storage as bs} from "./libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "../Base/libraries/Storage.sol";

/// @title LancaBridge
/// @notice Abstract bridge implementation for Lanca liquidity pools.
/// @dev
/// - Extends the `Base` pool and implements cross-chain liquidity bridging using Concero.
/// - Responsibilities:
///   * Collect liquidity from users and send cross-chain bridge messages.
///   * Charge and account for Lanca / rebalancer / LP fees.
///   * Receive bridge liquidity from other chains and deliver tokens to end users.
///   * Optionally call receiver hooks (`ILancaClient`) on the destination.
/// - This contract is intended to be inherited by concrete pool implementations
///   (e.g. `ChildPool`, `ParentPool`) that share the same bridge logic.
abstract contract LancaBridge is ILancaBridge, Base {
    using SafeERC20 for IERC20;
    using BridgeCodec for address;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;
    using MessageCodec for bytes;
    using s for s.Base;
    using rs for rs.Rebalancer;
    using bs for bs.Bridge;

    uint32 internal constant BRIDGE_GAS_OVERHEAD = 150_000;

    /// @inheritdoc ILancaBridge
    function bridge(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external payable returns (bytes32 messageId) {
        s.Base storage s_base = s.base();

        bytes32 dstPool = s_base.dstPools[dstChainSelector];
        require(dstPool != bytes32(0), InvalidDstChainSelector(dstChainSelector));

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        {
            uint256 amountAfterFee = _chargeTotalLancaFee(tokenAmount);

            messageId = _sendMessage(
                amountAfterFee,
                dstChainSelector,
                payload,
                dstChainData,
                dstPool,
                s_base
            );

            s_base.totalLiqTokenSent += amountAfterFee;
            s_base.flowByDay[getTodayStartTimestamp()].inflow += amountAfterFee;
        }

        emit BridgeSent(messageId, dstChainSelector, dstChainData, msg.sender, tokenAmount);
    }

    /*   INTERNAL FUNCTIONS   */

    /// @notice Internal helper to build and send a Concero bridge message.
    /// @dev
    /// - Uses:
    ///   * `dstPool` as destination receiver address,
    ///   * `validatorLib` / `relayerLib` from `s_base`,
    ///   * `BridgeCodec.encodeBridgeData` to encode bridge payload with:
    ///     - sender,
    ///     - receiver,
    ///     - tokenAmount,
    ///     - local token decimals,
    ///     - user payload.
    /// - Forwards `msg.value` to the Concero router as native fee.
    /// @param tokenAmount Amount to be bridged after fees, expressed in local decimals.
    /// @param dstChainSelector Destination chain selector.
    /// @param payload Optional user payload to be forwarded to the receiver hook.
    /// @param userDstChainData User-provided destination chain data.
    /// @param dstPool Bytes32-encoded destination pool address.
    /// @param s_base Storage reference to the base pool state.
    /// @return messageId Concero message identifier returned by `conceroSend`.
    function _sendMessage(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata payload,
        bytes calldata userDstChainData,
        bytes32 dstPool,
        s.Base storage s_base
    ) internal returns (bytes32) {
        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        (address receiver, uint32 userDstChainGasLimit) = MessageCodec.decodeEvmDstChainData(
            userDstChainData
        );

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: dstChainSelector,
            srcBlockConfirmations: 0,
            feeToken: address(0),
            dstChainData: _buildDstChainData(userDstChainGasLimit, dstPool, payload.length),
            validatorLibs: validatorLibs,
            relayerLib: s_base.relayerLib,
            validatorConfigs: new bytes[](1),
            relayerConfig: new bytes(0),
            payload: BridgeCodec.encodeBridgeData(
                msg.sender,
                receiver,
                tokenAmount,
                i_liquidityTokenDecimals,
                payload
            )
        });

        return IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(messageRequest);
    }

    /// @notice Builds the destination chain data for a bridge message.
    /// @dev
    /// - Enforces consistency:
    ///   * either both `userDstChainGasLimit` and `payloadLength` are zero (no hook),
    ///   * or both are non-zero (hook call is expected).
    /// - Returns encoded EVM destination data with:
    ///   * `receiver = dstPool.toAddress()`,
    ///   * `gasLimit = BRIDGE_GAS_OVERHEAD + userDstChainGasLimit`.
    /// - Reverts with `InvalidDstGasLimitOrCallData` on inconsistent input.
    /// @param userDstChainGasLimit User-provided destination chain gas limit.
    /// @param dstPool Bytes32-encoded destination pool address.
    /// @param payloadLength Length of the payload that may be sent to the receiver hook.
    /// @return Encoded `dstChainData` for the Concero message.
    function _buildDstChainData(
        uint32 userDstChainGasLimit,
        bytes32 dstPool,
        uint256 payloadLength
    ) internal pure returns (bytes memory) {
        require(
            (userDstChainGasLimit == 0 && payloadLength == 0) ||
                (userDstChainGasLimit > 0 && payloadLength > 0),
            InvalidDstGasLimitOrCallData()
        );

        return
            MessageCodec.encodeEvmDstChainData(
                dstPool.toAddress(),
                BRIDGE_GAS_OVERHEAD + userDstChainGasLimit
            );
    }

    /// @dev
    /// - Handles Concero bridge liquidity messages (`ConceroMessageType.BRIDGE`).
    /// - Steps:
    ///   1. Decodes bridge data:
    ///      * `tokenAmount`, `decimals`, `tokenSender`, `tokenReceiver`, `payload`.
    ///   2. Converts `tokenAmount` from source decimals to local decimals.
    ///   3. Updates outflow accounting via `_handleOutflow`.
    ///   4. Calls `_deliverBridge` to transfer tokens to the final receiver and optional hook.
    /// @param messageId Concero message ID.
    /// @param srcChainSelector Source chain selector.
    /// @param nonce Concero message nonce for this bridge.
    /// @param messageData Encoded bridge data payload.
    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 srcChainSelector,
        uint256 nonce,
        bytes calldata messageData
    ) internal override {
        (
            uint256 tokenAmount,
            uint8 decimals,
            bytes32 tokenSender,
            bytes32 tokenReceiver,
            bytes calldata payload
        ) = messageData.decodeBridgeData();

        tokenAmount = _toLocalDecimals(tokenAmount, decimals);

        _handleOutflow(tokenAmount, srcChainSelector, nonce);

        _deliverBridge(
            messageId,
            tokenAmount,
            srcChainSelector,
            tokenSender,
            tokenReceiver,
            payload
        );
    }

    /// @notice Delivers bridged tokens to the final receiver and optionally calls the Lanca hook.
    /// @dev
    /// - Decodes `receiver` from bytes32 to address.
    /// - Validates receiver and payload via `_validateBridgeParams`:
    ///   * if no hook should be called: only transfers tokens,
    ///   * if hook should be called:
    ///     - requires `receiver` to be a contract implementing `ILancaClient`.
    /// - Transfers `tokenAmount` to `receiver`.
    /// - If `shouldCallHook`, calls:
    ///   `ILancaClient(receiver).lancaReceive(...)`.
    /// - Emits `BridgeDelivered` after successful delivery.
    /// @param messageId Concero message ID.
    /// @param tokenAmount Amount to deliver (in local decimals).
    /// @param srcChainSelector Source chain selector.
    /// @param tokenSender Bytes32-encoded address of the original sender on the source chain.
    /// @param tokenReceiver Bytes32-encoded address of the receiver on the destination chain.
    /// @param payload Optional payload forwarded to the receiver hook.
    function _deliverBridge(
        bytes32 messageId,
        uint256 tokenAmount,
        uint24 srcChainSelector,
        bytes32 tokenSender,
        bytes32 tokenReceiver,
        bytes calldata payload
    ) internal {
        address receiver = tokenReceiver.toAddress();
        bool shouldCallHook = _validateBridgeParams(receiver, payload);

        IERC20(i_liquidityToken).safeTransfer(receiver, tokenAmount);

        if (shouldCallHook) {
            ILancaClient(receiver).lancaReceive(
                messageId,
                srcChainSelector,
                tokenSender,
                tokenAmount,
                payload
            );
        }

        emit BridgeDelivered(messageId, tokenAmount);
    }

    /// @notice Handles incoming bridged liquidity inflow accounting.
    /// @dev
    /// - Ensures the pool has enough active balance to cover the `tokenAmount`.
    /// - Uses `receivedBridges[srcChainSelector][nonce]` to support potential reorgs:
    ///   * if first time seen (existingAmount == 0):
    ///     - increases `totalLiqTokenReceived` by `tokenAmount`,
    ///   * if already present:
    ///     - adjusts `totalLiqTokenReceived` by the delta
    ///     - emits `SrcBridgeReorged` for the previous amount.
    /// - Updates:
    ///   * `receivedBridges[srcChainSelector][nonce]`,
    ///   * daily outflow for `getTodayStartTimestamp()`.
    /// - Reverts with `InvalidAmount` if `getActiveBalance() < tokenAmount`.
    /// @param tokenAmount Amount of tokens received (in local decimals).
    /// @param srcChainSelector Source chain selector.
    /// @param nonce Concero message nonce for this bridge.
    function _handleOutflow(uint256 tokenAmount, uint24 srcChainSelector, uint256 nonce) internal {
        bs.Bridge storage s_bridge = bs.bridge();
        s.Base storage s_base = s.base();

        require(getActiveBalance() >= tokenAmount, ICommonErrors.InvalidAmount());

        uint256 existingAmount = s_bridge.receivedBridges[srcChainSelector][nonce];

        if (existingAmount == 0) {
            s_base.totalLiqTokenReceived += tokenAmount;
        } else {
            s_base.totalLiqTokenReceived =
                s_base.totalLiqTokenReceived -
                existingAmount +
                tokenAmount;
            emit SrcBridgeReorged(srcChainSelector, existingAmount);
        }

        s_bridge.receivedBridges[srcChainSelector][nonce] = tokenAmount;
        s.base().flowByDay[getTodayStartTimestamp()].outflow += tokenAmount;
    }

    /// @notice Validates whether a hook should be called on the receiver and whether it is valid.
    /// @dev
    /// - If `payload.length == 0`:
    ///   * no hook is called, returns `false`.
    /// - Otherwise:
    ///   * requires `_isValidContractReceiver(receiver) == true`,
    ///   * returns `true`.
    /// - Reverts with `InvalidConceroMessage` if receiver is invalid while a hook is expected.
    /// @param receiver Receiver address on this chain.
    /// @param payload Hook payload (if any).
    /// @return shouldCallHook `true` if a hook call should be made after transfer.
    function _validateBridgeParams(
        address receiver,
        bytes calldata payload
    ) internal view returns (bool) {
        bool shouldCallHook = !(payload.length == 0);

        if (shouldCallHook && !_isValidContractReceiver(receiver)) {
            revert InvalidConceroMessage();
        }

        return shouldCallHook;
    }

    /// @notice Checks if a given receiver is a valid Lanca client contract.
    /// @dev
    /// - Requirements:
    ///   * `receiver.code.length > 0` (must be a contract),
    ///   * `receiver` supports `ILancaClient` interface via ERC-165.
    /// @param tokenReceiver Address of the potential receiver.
    /// @return True if `tokenReceiver` is a valid Lanca client, false otherwise.
    function _isValidContractReceiver(address tokenReceiver) internal view returns (bool) {
        if (
            tokenReceiver.code.length == 0 ||
            !IERC165(tokenReceiver).supportsInterface(type(ILancaClient).interfaceId)
        ) {
            return false;
        }

        return true;
    }

    /// @notice Charges all Lanca-related fees and returns the net bridged amount.
    /// @dev
    /// - Computes:
    ///   * `bridgeFee = getLancaFee(tokenAmount)`,
    ///   * `rebalancerFee = getRebalancerFee(tokenAmount)`,
    ///   * `lpFee = getLpFee(tokenAmount)`.
    /// - Updates:
    ///   * `totalLancaFeeInLiqToken += bridgeFee`,
    ///   * `totalRebalancingFeeAmount += rebalancerFee`.
    /// - Returns `tokenAmount - (lpFee + bridgeFee + rebalancerFee)`.
    /// @param tokenAmount Gross amount before fees.
    /// @return Net amount after all Lanca-related fees.
    function _chargeTotalLancaFee(uint256 tokenAmount) internal returns (uint256) {
        uint256 bridgeFee = getLancaFee(tokenAmount);
        uint256 rebalancerFee = getRebalancerFee(tokenAmount);

        uint256 totalLancaFee = getLpFee(tokenAmount) + bridgeFee + rebalancerFee;

        s.base().totalLancaFeeInLiqToken += bridgeFee;
        rs.rebalancer().totalRebalancingFeeAmount += rebalancerFee;

        return tokenAmount - totalLancaFee;
    }

    /*   GETTERS   */

    /// @inheritdoc ILancaBridge
    function getBridgeNativeFee(
        uint256 /* tokenAmount */,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external view returns (uint256) {
        s.Base storage s_base = s.base();

        bytes32 dstPool = s_base.dstPools[dstChainSelector];
        require(dstPool != bytes32(0), InvalidDstChainSelector(dstChainSelector));

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        (address receiver, uint32 userDstChainGasLimit) = MessageCodec.decodeEvmDstChainData(
            dstChainData
        );

        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                IConceroRouter.MessageRequest({
                    dstChainSelector: dstChainSelector,
                    srcBlockConfirmations: 0,
                    feeToken: address(0),
                    dstChainData: _buildDstChainData(userDstChainGasLimit, dstPool, payload.length),
                    validatorLibs: validatorLibs,
                    relayerLib: s_base.relayerLib,
                    validatorConfigs: new bytes[](1),
                    relayerConfig: new bytes(0),
                    payload: BridgeCodec.encodeBridgeData(
                        msg.sender,
                        receiver,
                        1,
                        i_liquidityTokenDecimals,
                        payload
                    )
                })
            );
    }
}
